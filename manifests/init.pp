# GOAL: 
#   Test various things in a file which will not affect the rest of the system

incude stdlib

class testing::test_output {

  notice( 'This message stays on the server, in the puppet logs' )
 
  notify{ 'This message goes to the client': }

}


# Test a hiera lookup. This is useful for checking the hierarchy
# This is done by assigning 'testdata' in each hiera file to the name of the file
class testing::test_hiera {

  $v = hiera(testdata, 'default')

  notify{ "DEBUG testing::test_hiera testdata = $v": }
}

# Test Puppet 3's auto binding for parameterized classes
class testing::test_hiera_auto_binding {
  notify{ "DEBUG testing: package = $package, testing::package = $testing::package, params = $params, testing::params = $testing::params": }

  # The hash can be extracted and then read
  $v1 = $testing::params
  $v2 = $v1[param1]
  notify{ "DEBUG testing: v1 = $v1, v2 = $v2": }

  # This reads an element from the hash directly
  $v3 = $testing::params[param1]
  notify{ "DEBUG testing: v3 = $v3": }

  # This reads a parameter from the hash in a hash parameter
  $v4 = $testing::params[param3][param4]
  notify{ "DEBUG testing: v4 = $v4": }

  # This reads a parameter from the hash in a hash parameter
  $v5 = $testing::params[param3][param6][param7]
  notify{ "DEBUG testing: v5 = $v5": }
}

# This is here for posterity
# It was useful before Puppet 3's auto-binding
# It's useful to describe the hash fetching and merging functions
class testing::describe_hiera_merge {

  # $d = {
  #   'package' => 'jdk',
  #   'version' => 'present'
  # }

  # $h = hiera_hash('jdk')  # hiera_hash('jdk',$d) only applies if 'jdk' is not found, and the entire hash variable is undefined

  # $p = merge( $d, $h )    # puppetlabs/stdlib#merge 'prefers' elements in the 2nd hash

  # package { $p['package'] :
  #   ensure => $p['version'],
  #   require => Yumrepo["local_yum_puppet_repo"],
  # }

}


# Run this in the VM to perform a hiera lookup
class testing::check_hiera {

  $f = '/usr/local/bin/check_hiera'

  file { $f:
    content => "hiera -c /opt/puppet/hiera.yaml --debug \$1 env=$env role=$role",
    owner => 0, group => 0, mode => 0755
  }

  notify{ "You can run a hiera lookup by executing $f <ARG>": }

}


# This allows us to run a shell command in the VM to see the effects of Puppet changes, without rebooting
class testing::apply_puppet {

  $f = '/usr/local/bin/apply_puppet'

  # Use the custom facts to create the test command
  # http://docs.puppetlabs.com/references/stable/configuration.html
  file { $f:
    content => "sudo sh -c 'export FACTER_env='$env'; export FACTER_role='$role'; puppet apply --debug --hiera_config /opt/puppet/hiera.yaml --modulepath /opt/puppet/modules --graph --graphdir /opt/puppet/graphs /opt/puppet/manifests/site.pp | tee /var/log/puppet/apply_puppet.log'",
    owner => 0, group => 0, mode => 0755
  }

  notify{ "You can run a local 'puppet apply' by executing $f": }

}


# Filter 'apply_puppet' to only show notices starting with "DEBUG"
class testing::debug_puppet {

  $f = '/usr/local/bin/debug_puppet'

  file { $f:
    content => "apply_puppet | grep 'Notice: DEBUG'",
    owner => vagrant, group => vagrant, mode => 0755
  }

  notify{ "You can run a local 'puppet apply' by executing $f": }

}

# Run "java -version" and store the result as a custom fact
#
# Note: this is A BAD PATTERN 
#  - it's not portable (it's a shell command)
#  - it's not idempotent (the fact will not be used until the next puppet run because facter has already read/set the facts)
#  - it relies on puppetlabs/stdlib (that's not too bad)
#
# This could be fixed by running this before puppet, say in Vagrant's shell provisioner, or via ssh (for remote machines)
#
class testing::custom_fact_java_version {

  notify{ "DEBUG java_version (as of the previous fact run) is $::java_version": }

  # Create a fact which will be picked up in subsequent fact runs

  # facter-dot-d will be standard in Facter, later
  # https://puppetlabs.com/blog/module-of-the-week-puppetlabsstdlib-puppetlabs-standard-library-part-3/
  #
  #file { ["/etc/facter", "/etc/facter/facts.d"]:
  #  ensure => "directory",
  #  owner  => 0, 
  #  group  => 0, 
  #  mode   => 775,
  #}
  #
  #$cmd = 'echo "java_version: `java -version 2>&1 | grep version | perl -pi -e \'s/.*"(.*)"/\$1/\' `" > /etc/facter/facts.d/java_version.yaml'
  #exec { "update_java_version_fact":
  #  command => $cmd,
  #  path    => "/usr/bin/:/bin/",
  #  require => File['/etc/facter/facts.d'],
  #}  

  # This doesn't take effect until a login (or sourcing the file)
  $cmd = 'echo "export FACTER_java_version=`java -version 2>&1 | grep version | perl -pi -e \'s/.*"(.*)"/\$1/\' `" > /etc/profile.d/puppet_facts.sh'
  exec { "update_java_version_fact":
    command => $cmd,
    path    => "/usr/bin/:/bin/",
  }  


}

class testing::motd {

  $t = strftime("%F %r")  # https://forge.puppetlabs.com/puppetlabs/stdlib

  file { '/etc/motd':
    content => "Welcome to a puppet-managed node 
  OS: $operatingsystem $operatingsystemrelease $lsbdistcodename $kernelrelease 
  Memory: $memoryfree / $memorysize
  Swap: $swapfree / $swapsize
  CPU: $processorcount x $processor0
  Host: $hostname.$domain ($clientcert) 
  Virtual: $is_virtual $virtual
  Updated: $t $timezone
  java_version (as of the previous fact run): $::java_version 
  env = $env
  role = $role
",
    owner => 0, group => 0, mode => 0644,
  }

}

#
# Test and demonstrate current best practices: Puppet 3, driven by hiera
#
# http://docs.puppetlabs.com/puppet/3/reference/release_notes.html
# http://docs.puppetlabs.com/puppet/3/reference/release_notes.html#automatic-data-bindings-for-class-parameters-1
#
class testing(
  $tested_oses = 'ubuntu|centos|oraclelinux', # Documents the OSes that were tested during development
  $params  # no default since we want to fail if hiera doesn't find and bind this
) {

  notify { "DEBUG testing: tested_oses = $tested_oses, params = $params": } 

  # Sanity check parameters
  # The puppetlabs/stdlib functions are useful for this
  # https://github.com/puppetlabs/puppetlabs-stdlib
  #
  validate_hash($params)
  validate_re( $params[param1], '^val.*$') # Make sure param1 starts with 'val'

  # Require Puppet 3 
  validate_re( $::puppetversion, '^3.', "We need Puppet 3, but this is $::puppetversion. This requirement avoids possible behavior differences.")

  # Choke on an untested OS
  $downcaseos = downcase( $::operatingsystem ) 
  validate_re( $downcaseos, $tested_oses, "The operating system is $downcaseos, which is not tested ($tested_oses).") 
  notify { "DEBUG testing: OS is $downcaseos, which is tested ($tested_oses)": } 

  # Generic tests
  include testing::test_output
  include testing::test_hiera
  include testing::test_hiera_auto_binding

  # Allow skipping some tests on some OSes (ugly)
  #
  # TODO: enhance these so they can run on any OS
  case $::operatingsystem {
    centos, ubuntu, oraclelinux: {  # redhat, fedora, debian # TODO: add these as testing is done on them
      notify { "DEBUG testing: adding useful os-specific testing stuff": }
      include testing::check_hiera
      include testing::apply_puppet
      include testing::debug_puppet
      include testing::custom_fact_java_version
      include testing::motd 
    }
    default: { 
      notify { "DEBUG testing: skipping os-specific testing stuff": }
    }
  }

}


