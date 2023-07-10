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
# @param service_name
#   Service name for gss_service.
#
# @param gss_line
#   GSS line to set to 'yes', if $nfs_config_method is 'sysconfig'.
#
# @param keytab_line
#   Keytab line to set to '-k ${keytab}\', if $nfs_config_method is 'sysconfig'.
#
# @param nfs_sysconf
#   Path to NFS config file, if $nfs_config_method is 'sysconfig'.
#
# @param nfs_config_method
#   Method of NFS service configuration. Either 'sysconfig' or 'service'.
#
# @param service
#   Name of RPC service.
#
class nfsclient (
  Boolean                        $gss               = false,
  Optional[Stdlib::Absolutepath] $keytab            = undef,
  Optional[String[1]]            $service_name      = undef,
  Optional[String[1]]            $gss_line          = undef,
  Optional[String[1]]            $keytab_line       = undef,
  Stdlib::Absolutepath           $nfs_sysconf       = '/etc/sysconfig/nfs',
  String[1]                      $nfs_config_method = 'sysconfig',
  String[1]                      $service           = 'rpc-gssd',
) {
  case $facts['os']['name'] {
    'RedHat': {
      include nfs::idmap
      $nfs_requires = Service['idmapd_service']
    }
    default: {
      $nfs_requires = undef
    }
  }

  if $gss {
    $_gssd_options_notify = [Service['rpcbind_service'], Service[$service]]

    include rpcbind

    if $nfs_config_method == 'sysconfig' {
      file_line { 'NFS_SECURITY_GSS':
        path   => $nfs_sysconf,
        line   => "${gss_line}=\"yes\"",
        match  => "^${gss_line}=.*",
        notify => Service['rpcbind_service'],
      }
    } elsif $nfs_config_method == 'service' {
      service { 'gss_service':
        ensure => 'running',
        name   => $service_name,
        enable => true,
      }
    }

    $service_subscribe = $nfs_config_method ? {
      'sysconfig' => File_line['NFS_SECURITY_GSS'],
      'service'   => Service['gss_service'],
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
        notify => [Service[$service], Service['rpcbind_service']],
      }
      file_line { 'MODULES_LOADED_ON_BOOT':
        match  => '^MODULES_LOADED_ON_BOOT=',
        path   => '/etc/sysconfig/kernel',
        line   => 'MODULES_LOADED_ON_BOOT="rpcsec_gss_krb5"',
        notify => Exec['gss-module-modprobe'],
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
