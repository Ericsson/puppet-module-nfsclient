require 'spec_helper'

describe 'nfsclient', type: :class do
  on_supported_os.sort.each do |os, facts|
    describe "on #{os}" do
      let(:facts) { facts }

      # define os specific defaults
      case facts[:os]['family']
      when 'RedHat'
        service_name      = 'auth-rpcgss-module.service'
        gss_line          = 'SECURE_NFS'
        keytab_line       = 'RPCGSSDARGS'
        nfs_requires      = 'Service[idmapd_service]'
        case facts[:os]['release']['major']
        when '6'
          service           = 'rpcgssd'
          nfs_config_method = 'sysconfig'
        when '7'
          nfs_config_method = 'sysconfig'
        else
          nfs_config_method = 'service'
        end
      when 'Suse'
        gss_line          = 'NFS_SECURITY_GSS'
        keytab_line       = 'GSSD_OPTIONS'
        case facts[:os]['release']['major']
        when '11'
          service           = 'nfs'
        end
      when 'Debian'
        gss_line          = 'NEED_GSSD'
        keytab_line       = 'GSSDARGS'
        nfs_sysconf       = '/etc/default/nfs-common'
      end

      # use module defaults otherwise
      nfs_sysconf       = '/etc/sysconfig/nfs' if nfs_sysconf.nil?
      nfs_config_method = 'sysconfig' if nfs_config_method.nil?
      service           = 'rpc-gssd' if service.nil?

      context 'with all defaults' do
        let(:params) { {} }

        it { is_expected.to contain_class('nfsclient') }
        it { is_expected.to compile.with_all_deps }

        if facts[:os]['family'] == 'RedHat'
          it { is_expected.to contain_class('nfs::idmap') }
          it { is_expected.to have_resource_count(3) } # from nfs::idmap
        else
          it { is_expected.to have_resource_count(0) }
        end
      end

      context 'with gss set to valid true' do
        let(:params) { { gss: true } }

        it { is_expected.to contain_class('rpcbind') }

        if nfs_config_method == 'sysconfig'
          it do
            is_expected.to contain_file_line('NFS_SECURITY_GSS').only_with(
              {
                'path'   => nfs_sysconf,
                'line'   => "#{gss_line}=\"yes\"",
                'match'  => "^#{gss_line}=.*",
                'notify' => 'Service[rpcbind_service]',
              },
            )
          end
          service_subscribe = 'File_line[NFS_SECURITY_GSS]'
        else
          it do
            is_expected.to contain_service('gss_service').only_with(
              {
                'ensure' => 'running',
                'name'   => service_name,
                'enable' => true,
              },
            )
          end
          service_subscribe = 'Service[gss_service]'
        end

        it do
          is_expected.to contain_service(service).only_with(
            {
              'ensure'    => 'running',
              'enable'    => true,
              'subscribe' => service_subscribe,
              'require'   => nfs_requires,
            },
          )
        end

        if "#{facts[:os]['family']}-#{facts[:os]['release']['major']}" == 'Suse-11'
          it do
            is_expected.to contain_file_line('NFS_START_SERVICES').only_with(
              {
                'match'  => '^NFS_START_SERVICES=',
                'path'   => '/etc/sysconfig/nfs',
                'line'   => 'NFS_START_SERVICES="yes"',
                'notify' => ['Service[nfs]', 'Service[rpcbind_service]'],
              },
            )
          end

          it do
            is_expected.to contain_file_line('MODULES_LOADED_ON_BOOT').only_with(
              {
                'match'  => '^MODULES_LOADED_ON_BOOT=',
                'path'   => '/etc/sysconfig/kernel',
                'line'   => 'MODULES_LOADED_ON_BOOT="rpcsec_gss_krb5"',
                'notify' => 'Exec[gss-module-modprobe]',
              },
            )
          end

          it do
            is_expected.to contain_exec('gss-module-modprobe').only_with(
              {
                'command'     => 'modprobe rpcsec_gss_krb5',
                'unless'      => 'lsmod | egrep "^rpcsec_gss_krb5"',
                'path'        => '/sbin:/usr/bin',
                'refreshonly' => true,
              },
            )
          end
        else
          it { is_expected.not_to contain_file_line('NFS_START_SERVICES') }
          it { is_expected.not_to contain_file_line('MODULES_LOADED_ON_BOOT') }
          it { is_expected.not_to contain_exec('gss-module-modprobe') }
        end
      end

      context 'with keytab set to valid value' do
        let(:params) { { keytab: '/test/ing' } }

        if nfs_config_method == 'sysconfig'
          it do
            is_expected.to contain_file_line('GSSD_OPTIONS').only_with(
              {
                'path'   => nfs_sysconf,
                'line'   => "#{keytab_line}=\"-k /test/ing\"",
                'match'  => "^#{keytab_line}=.*",
                'notify' => nil,
              },
            )
          end
        end

        if "#{facts[:os]['family']}-#{facts[:os]['release']['major']}" == 'RedHat-7'
          it do
            is_expected.to contain_exec('nfs-config').only_with(
              {
                'command'     => 'service nfs-config start',
                'path'        => '/sbin:/usr/sbin',
                'refreshonly' => true,
                'subscribe'   => 'File_line[GSSD_OPTIONS]',
              },
            )
          end
        end
      end

      context 'with service_name set to valid value when gss is true' do
        let(:params) { { service_name: 'testing', gss: true } }

        if nfs_config_method == 'service'
          it { is_expected.to contain_service('gss_service').with_name('testing') }
        end
      end

      context 'with gss_line set to valid value when gss is true' do
        let(:params) { { gss_line: 'testing', gss: true } }

        if nfs_config_method == 'sysconfig'
          it { is_expected.to contain_file_line('NFS_SECURITY_GSS').with_line('testing="yes"') }
          it { is_expected.to contain_file_line('NFS_SECURITY_GSS').with_match('^testing=.*') }
        end
      end

      context 'with keytab_line set to valid value when keytab is valid' do
        let(:params) { { keytab_line: 'testing', keytab: '/dummy' } }

        if nfs_config_method == 'sysconfig'
          it { is_expected.to contain_file_line('GSSD_OPTIONS').with_line('testing="-k /dummy"') }
          it { is_expected.to contain_file_line('GSSD_OPTIONS').with_match('^testing=.*') }
        end
      end

      context 'with nfs_sysconf set to valid value when gss is true and keytab is valid' do
        let(:params) { { nfs_sysconf: '/test/ing', gss: true, keytab: '/dummy' } }

        if nfs_config_method == 'sysconfig'
          it { is_expected.to contain_file_line('NFS_SECURITY_GSS').with_path('/test/ing') }
          it { is_expected.to contain_file_line('GSSD_OPTIONS').with_path('/test/ing') }
        end
      end

      context 'with nfs_config_method set to valid service when gss is true and keytab is valid' do
        let(:params) { { nfs_config_method: 'service', gss: true, keytab: '/dummy' } }

        it { is_expected.not_to contain_file_line('NFS_SECURITY_GSS') }
        it { is_expected.to contain_service('gss_service') }
        it { is_expected.to contain_service(service).with_subscribe('Service[gss_service]') }
        it { is_expected.not_to contain_file_line('GSSD_OPTIONS') }
      end

      context 'with nfs_config_method set to valid sysconfig when gss is true and keytab is valid' do
        let(:params) { { nfs_config_method: 'sysconfig', gss: true, keytab: '/dummy' } }

        it { is_expected.to contain_file_line('NFS_SECURITY_GSS') }
        it { is_expected.not_to contain_service('gss_service') }
        it { is_expected.to contain_service(service).with_subscribe('File_line[NFS_SECURITY_GSS]') }
        it { is_expected.to contain_file_line('GSSD_OPTIONS') }
      end

      context 'with service set to valid value when gss is true and keytab is valid' do
        let(:params) { { service: 'testing', gss: true, keytab: '/dummy' } }

        it { is_expected.to contain_service('testing') }

        if nfs_config_method == 'sysconfig'
          it { is_expected.to contain_file_line('GSSD_OPTIONS').with_notify(['Service[rpcbind_service]', 'Service[testing]']) }
        end
      end

      # nfs::idmap does not support Debian so we need to skip it
      if facts[:os]['family'] != 'Debian'
        context 'with include_idmap set to valid true' do
          let(:params) { { include_idmap: true } }

          it { is_expected.to contain_class('nfs::idmap') }
        end
      end

      # nfs::idmap is only supported on RedHat
      if facts[:os]['family'] == 'RedHat'
        context 'with include_idmap set to valid true when gss is true' do
          let(:params) { { include_idmap: true, gss: true } }

          it { is_expected.to contain_class('nfs::idmap') }
          it { is_expected.to contain_service(service).with_require('Service[idmapd_service]') }
        end
      end

      context 'with include_nfs_config set to valid true when keytab is valid and nfs_config_method is sysconfig' do
        let(:params) { { include_nfs_config: true, keytab: '/dummy', nfs_config_method: 'sysconfig' } }

        it do
          is_expected.to contain_exec('nfs-config').only_with(
            {
              'command'     => 'service nfs-config start',
              'path'        => '/sbin:/usr/sbin',
              'refreshonly' => true,
              'subscribe'   => 'File_line[GSSD_OPTIONS]',
            },
          )
        end
      end

      context 'with include_nfs_config set to valid true when gss is true and keytab is valid' do
        let(:params) { { include_nfs_config: true, gss: true, keytab: '/dummy' } }

        it { is_expected.to contain_exec('nfs-config').with_notify(["Service[#{service}]"]) }
        it { is_expected.to contain_Service('rpcbind_service').with_before(["Service[#{service}]"]) }
      end

      context 'with include_nfs_config set to valid true when keytab is valid and nfs_config_method is service' do
        let(:params) { { include_nfs_config: true, keytab: '/dummy', nfs_config_method: 'service' } }

        it do
          is_expected.to contain_exec('nfs-config').only_with(
            {
              'command'     => 'service nfs-config start',
              'path'        => '/sbin:/usr/sbin',
              'refreshonly' => true,
              'subscribe'   => nil,
            },
          )
        end
      end

      context 'with include_sysconfig set to valid true when gss is true' do
        let(:params) { { include_sysconfig: true, gss: true, nfs_config_method: 'sysconfig' } }

        it do
          is_expected.to contain_file_line('NFS_START_SERVICES').only_with(
            {
              'match'  => '^NFS_START_SERVICES=',
              'path'   => '/etc/sysconfig/nfs',
              'line'   => 'NFS_START_SERVICES="yes"',
              'notify' => ["Service[#{service}]", 'Service[rpcbind_service]'],
            },
          )
        end

        it do
          is_expected.to contain_file_line('MODULES_LOADED_ON_BOOT').only_with(
            {
              'match'  => '^MODULES_LOADED_ON_BOOT=',
              'path'   => '/etc/sysconfig/kernel',
              'line'   => 'MODULES_LOADED_ON_BOOT="rpcsec_gss_krb5"',
              'notify' => 'Exec[gss-module-modprobe]',
            },
          )
        end

        it do
          is_expected.to contain_exec('gss-module-modprobe').only_with(
            {
              'command'     => 'modprobe rpcsec_gss_krb5',
              'unless'      => 'lsmod | egrep "^rpcsec_gss_krb5"',
              'path'        => '/sbin:/usr/bin',
              'refreshonly' => true,
            },
          )
        end
      end
    end
  end
end
