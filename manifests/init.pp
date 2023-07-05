# @summary Puppet module to manage nfs client configuration.
#
#   # Note
#   This module does not manage /etc/krb5.keytab any more.
#   Use a Keberos module such as [kodguru/puppet-module-krb5](https://github.com/kodguru/puppet-module-krb5/)
#   (version 0.8.0 or newer) if you need to manage Kerberos itself.
#
#   To ensure the service in restarted when /etc/krb5.keytab is updated you could
#   add logic similar to the code below in your profile to ensure it occurs.
#
#   ```
#   ...
#   include nfsclient
#   include krb5
#
#   if defined(File['krb5keytab_file']) {
#     File['krb5keytab_file'] ~> Class['nfsclient']
#   }
#   ...
#   ```
#   If statement is in case File['krb5keytab_file'] is relevant if it could be catalogues
#   missing this resource.
#
# @param gss
#   Enable GSS.
#
# @param keytab
#   Location of keytab.
#
class nfsclient (
  Boolean $gss                           = false,
  Optional[Stdlib::Absolutepath] $keytab = undef,
) {
  case $facts['os']['family'] {
    'RedHat': {
      $nfs_config_method = $facts['os']['release']['full'] ? {
        /^[67]/ => 'sysconfig',
        default => 'service',
      }
      $module_service    = 'auth-rpcgss-module.service'
      $gss_line          = 'SECURE_NFS'
      $keytab_line       = 'RPCGSSDARGS'
      $nfs_sysconf       = '/etc/sysconfig/nfs'
      $nfs_requires      = Service['idmapd_service']
      $service           = $facts['os']['release']['full'] ? {
        /^6/    => 'rpcgssd',
        default => 'rpc-gssd',
      }
      include nfs::idmap
    }
    'Suse': {
      $nfs_config_method = 'sysconfig'
      $module_service    = undef
      $gss_line          = 'NFS_SECURITY_GSS'
      $keytab_line       = 'GSSD_OPTIONS'
      $nfs_sysconf       = '/etc/sysconfig/nfs'
      $nfs_requires      = undef
      $service           = $facts['os']['release']['full'] ? {
        /^11/   => 'nfs',
        default => 'rpc-gssd',
      }
    }
    'Debian': {
      if $facts['os']['name'] != 'Ubuntu' {
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
      fail("nfsclient module only supports Suse, RedHat and Ubuntu. <${facts['os']['family']}> was detected.")
    }
  }

  $service_subscribe = $nfs_config_method ? {
    'sysconfig' => File_line['NFS_SECURITY_GSS'],
    'service'   => Service['gss_service'],
  }

  if $gss {
    $_gssd_options_notify = [Service[rpcbind_service], Service[$service]]

    include rpcbind

    if $nfs_config_method == 'sysconfig' {
      file_line { 'NFS_SECURITY_GSS':
        path   => $nfs_sysconf,
        line   => "${gss_line}=\"yes\"",
        match  => "^${gss_line}=.*",
        notify => 'Service[rpcbind_service]',
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

    if "${facts['os']['family']}-${facts['os']['release']['full']}" =~ /^Suse-11/ {
      file_line { 'NFS_START_SERVICES':
        match  => '^NFS_START_SERVICES=',
        path   => '/etc/sysconfig/nfs',
        line   => 'NFS_START_SERVICES="yes"',
        notify => ['Service[nfs]', 'Service[rpcbind_service]'],
      }
      file_line { 'MODULES_LOADED_ON_BOOT':
        match  => '^MODULES_LOADED_ON_BOOT=',
        path   => '/etc/sysconfig/kernel',
        line   => 'MODULES_LOADED_ON_BOOT="rpcsec_gss_krb5"',
        notify => 'Exec[gss-module-modprobe]',
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

    if "${facts['os']['family']}-${facts['os']['release']['full']}" =~ /^RedHat-7/ {
      exec { 'nfs-config':
        command     => 'service nfs-config start',
        path        => '/sbin:/usr/sbin',
        refreshonly => true,
        subscribe   => File_line['GSSD_OPTIONS'],
      }
      if $gss {
        Exec['nfs-config'] ~> Service[$service]
        Service['rpcbind_service'] -> Service[$service]
      }
    }
  }
}
