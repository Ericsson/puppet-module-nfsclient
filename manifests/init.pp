# nfsclient class
#
# @summary Manage nfs client and secure communication (krb)
#
# @example Declaring the class
#   include nfsclient
#
# @param gss
#   Configure GSS. Class does nothing without this being set to true.
#
# @param keytab
#   Location of keytab file in configuration files.
class nfsclient (
  Variant[Boolean, String]   $gss    = false,
  Optional[Stdlib::Unixpath] $keytab = undef,
) {

  if is_bool($gss) == true {
    $gss_bool = $gss
  } else {
    $gss_bool = str2bool($gss)
  }

  case $::osfamily {
    'RedHat': {
      $nfs_config_method = $::operatingsystemrelease ? {
        /^[67]/ => 'sysconfig',
        default => 'service',
      }
      $module_service    = $::operatingsystemrelease ? {
        /^[678]/ => 'auth-rpcgss-module.service',
        default  => 'gssproxy',
      }
      $gss_line          = 'SECURE_NFS'
      $keytab_line       = 'RPCGSSDARGS'
      $nfs_sysconf       = '/etc/sysconfig/nfs'
      $nfs_requires      = $::operatingsystemrelease ? {
        /^[5678]/ => Service['idmapd_service'],
        default   => undef,
      }
      $service           = $::operatingsystemrelease ? {
        /^6/    => 'rpcgssd',
        default => 'rpc-gssd',
      }
      include ::nfs::idmap
    }
    'Suse': {
      $nfs_config_method = 'sysconfig'
      $module_service    = undef
      $gss_line          = 'NFS_SECURITY_GSS'
      $keytab_line       = 'GSSD_OPTIONS'
      $nfs_sysconf       = '/etc/sysconfig/nfs'
      $nfs_requires      = undef
      $service           = $::operatingsystemrelease ? {
        /^11/   => 'nfs',
        default => 'rpc-gssd',
      }
    }
    'Debian': {
      if $::operatingsystem != 'Ubuntu' {
        fail('nfsclient module only supports Suse, RedHat and Ubuntu. Debian was detected.')
      }
      $nfs_config_method = 'sysconfig'
      $module_service    = undef
      $gss_line          = 'NEED_GSSD'
      $keytab_line       = 'GSSDARGS'
      $nfs_sysconf       = '/etc/default/nfs-common'
      $nfs_requires      = undef
      $service           = 'rpc-gssd'

      # Puppet 3.x Incorrectly defaults to upstart for Ubuntu >= 16.x
      Service {
        provider => 'systemd',
      }
    }
    default: {
      fail("nfsclient module only supports Suse, RedHat and Ubuntu. <${::osfamily}> was detected.")
    }
  }

  $service_subscribe = $nfs_config_method ? {
    'sysconfig' => File_line['NFS_SECURITY_GSS'],
    'service'   => Service['gss_service'],
  }

  if $gss_bool {
    $_gssd_options_notify = [ Service[rpcbind_service], Service[$service] ]

    include ::rpcbind

    if $nfs_config_method == 'sysconfig' {
      file_line { 'NFS_SECURITY_GSS':
        path   => $nfs_sysconf,
        line   => "${gss_line}=\"yes\"",
        match  => "^${gss_line}=.*",
        notify => Service[rpcbind_service],
      }
    } elsif $nfs_config_method == 'service' {
      service { 'gss_service':
        ensure => 'running',
        name   => $module_service,
        enable => true,
      }
    }

    service { $service:
      ensure    => 'running',
      enable    => true,
      subscribe => $service_subscribe,
      require   => $nfs_requires,
    }

    if "${::osfamily}-${::operatingsystemrelease}" =~ /^Suse-11/ {
      file_line { 'NFS_START_SERVICES':
        match  => '^NFS_START_SERVICES=',
        path   => '/etc/sysconfig/nfs',
        line   => 'NFS_START_SERVICES="yes"',
        notify => [ Service[nfs], Service[rpcbind_service], ],
      }
      file_line { 'MODULES_LOADED_ON_BOOT':
        match  => '^MODULES_LOADED_ON_BOOT=',
        path   => '/etc/sysconfig/kernel',
        line   => 'MODULES_LOADED_ON_BOOT="rpcsec_gss_krb5"',
        notify => Exec[gss-module-modprobe],
      }
      exec { 'gss-module-modprobe':
        command     => 'modprobe rpcsec_gss_krb5',
        unless      => 'lsmod | egrep "^rpcsec_gss_krb5"',
        path        => '/sbin:/usr/bin',
        refreshonly => true,
      }
    }
  }
  else {
    $_gssd_options_notify = undef
  }

  if $keytab {
    if $nfs_config_method == 'sysconfig' {
      file_line { 'GSSD_OPTIONS':
        path   => $nfs_sysconf,
        line   => "${keytab_line}=\"-k ${keytab}\"",
        match  => "^${keytab_line}=.*",
        notify => $_gssd_options_notify,
      }
    }

    if "${::osfamily}-${::operatingsystemrelease}" =~ /^RedHat-7/ {
      exec { 'nfs-config':
        command     => 'service nfs-config start',
        path        => '/sbin:/usr/sbin',
        refreshonly => true,
        subscribe   => File_line['GSSD_OPTIONS'],
      }
      if $gss_bool {
        Exec['nfs-config'] ~> Service[$service]
        Service['rpcbind_service'] -> Service[$service]
      }
    }
  }
}
