require 'spec_helper'
describe 'nfsclient' do
  describe 'variable type and content validations' do
    # tests should be OS independent, so we only test RedHat
    test_on = {
      supported_os: [
        {
          'operatingsystem'        => 'RedHat',
          'operatingsystemrelease' => ['8'],
        },
      ],
    }
    on_supported_os(test_on).sort.each do |os, os_facts|
      context "on #{os}" do
        let(:facts) { os_facts }

        validations = {
          'Boolean' => {
            name:    ['gss', 'include_idmap', 'include_nfs_config', 'include_sysconfig'],
            valid:   [true, false],
            invalid: ['true', 'false', 'string', ['array'], { 'ha' => 'sh' }, 3, 2.42, nil],
            message: 'expects a Boolean',
          },
          'Enum[service, sysconfig]' => {
            name:    ['nfs_config_method'],
            valid:   ['service', 'sysconfig'],
            invalid: ['string', ['array'], { 'ha' => 'sh' }, 3, 2.42, false],
            message: 'expects a match for Enum',
          },
          'Optional[String[1]]' => {
            name:    ['service_name', 'gss_line', 'keytab_line'],
            valid:   ['valid'],
            invalid: [['array'], { 'ha' => 'sh' }],
            message: 'expects a value of type Undef or String',
          },
          'Stdlib::Absolutepath & Optional[Stdlib::Absolutepath]' => {
            name:    ['keytab', 'nfs_sysconf'],
            valid:   ['/absolute/filepath', '/absolute/directory/'], # cant test undef :(
            invalid: ['relative/path', 3, 2.42, ['array'], { 'ha' => 'sh' }],
            message: 'expects a Stdlib::Absolutepath',
          },
          'String[1]' => {
            name:    ['service'],
            valid:   ['string'],
            invalid: [['array'], { 'ha' => 'sh' }, 3, 2.42, true, false],
            message: 'expects a String',
          },
        }
        validations.sort.each do |type, var|
          var[:name].each do |var_name|
            var[:params] = {} if var[:params].nil?
            var[:valid].each do |valid|
              context "when #{var_name} (#{type}) is set to valid #{valid} (as #{valid.class})" do
                let(:params) { [var[:params], { "#{var_name}": valid, }].reduce(:merge) }

                it { is_expected.to compile }
              end
            end

            var[:invalid].each do |invalid|
              context "when #{var_name} (#{type}) is set to invalid #{invalid} (as #{invalid.class})" do
                let(:params) { [var[:params], { "#{var_name}": invalid, }].reduce(:merge) }

                it 'fail' do
                  expect { is_expected.to contain_class(:subject) }.to raise_error(Puppet::Error, %r{#{var[:message]}})
                end
              end
            end
          end
        end
      end
    end
  end
end
