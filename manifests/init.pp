# == Class: vas
#
# Puppet module to manage VAS - Quest Authentication Services
#
class vas (
  $package_version              = 'UNSET',
  $users_allow_entries          = ['UNSET'],
  $user_override_entries        = ['UNSET'],
  $username                     = 'username',
  $keytab_source                = 'UNSET',
  $keytab_target                = '/etc/vasinst.key',
  $computers_ou                 = 'ou=computers,ou=example,ou=com',
  $users_ou                     = 'ou=users,ou=example,ou=com',
  $nismaps_ou                   = 'ou=nismaps,ou=example,ou=com',
  $nisdomainname                = undef,
  $realm                        = 'realm.example.com',
  $sitenameoverride             = 'UNSET',
  $vas_conf_update_process      = '/opt/quest/libexec/vas/mapupdate_2307',
  $vas_conf_upm_computerou_attr = 'department',
  $vas_conf_client_addrs        = 'UNSET',
  $solaris_vasclntpath          = 'UNSET',
  $solaris_vasyppath            = 'UNSET',
  $solaris_vasgppath            = 'UNSET',
  $solaris_adminpath            = 'UNSET',
  $solaris_responsepattern      = 'UNSET',
) {

  case $::kernel {
    'Linux': {
      include vas::linux
    }
    'SunOS': {
      include vas::solaris
    }
    default: {
      fail("Vas module support Linux and SunOS kernels. Detected kernel is <${::kernel}>")
    }
  }

  include nisclient
  include nsswitch
  include pam

  # Use nisdomainname is supplied. If not, use nisclient::domainname if it
  # exists, last resort fall back to domain fact
  if $nisdomainname == undef {
    if $nisclient::domainname != undef {
      $my_nisdomainname = $nisclient::domainname
    } else {
      $my_nisdomainname = $::domain
    }
  }

  Package['vasclnt'] -> Package['vasyp'] -> Package['vasgp'] -> Exec['vasinst']

  file { '/etc/opt/quest/vas/vas.conf':
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('vas/vas.conf.erb'),
    require => Package['vasgp'],
  }

  file { '/etc/opt/quest/vas/users.allow':
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('vas/users.allow.erb'),
    require => Package['vasclnt','vasyp','vasgp'],
  }

  file { '/etc/opt/quest/vas/user-override':
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('vas/user-override.erb'),
    require => Package['vasclnt','vasyp','vasgp'],
    before  => Service['vasd','vasypd'],
  }

  file { $keytab_target:
    ensure => present,
    owner  => 'root',
    group  => 'root',
    mode   => '0400',
    source => "puppet:///${keytab_source}",
  }

  service { ['vasd','vasypd']:
    ensure    => running,
    enable    => true,
    subscribe => Exec['vasinst'],
    notify    => Service[$nisclient::service_name],
  }

  $s_opts = $sitenameoverride ? {
    'UNSET' => '',
    default => "-s ${sitenameoverride}",
  }

  $once_file = '/etc/opt/quest/vas/puppet_joined'

  exec { 'vasinst':
    command => "vastool -u ${username} -k ${keytab_target} -d3 join -f -c ${computers_ou} -p ${users_ou} -n ${::fqdn} ${s_opts} ${realm} >/var/tmp/vasjoin.log 2>&1 && touch ${once_file}",
    path    => '/bin:/usr/bin:/opt/quest/bin',
    timeout => 1200,
    creates => $once_file,
    require => File[$keytab_target],
    notify  => Exec['deps'],
  }
}
