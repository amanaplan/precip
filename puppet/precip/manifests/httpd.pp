class precip::httpd {
  # Need to specifically ask for Prefork, otherwise Ubuntu will go grab Worker
  # (Worker is weird)
  class { 'apache': mpm_module => "prefork" }
  class { 'apache::mod::php': }
  class { 'apache::mod::ssl': }
  class { 'apache::mod::rewrite': }

  # We'll need this when we make our vhosts
  file {"/var/www/site-php":
    ensure => "directory",
    mode => '0755',
  }

  # We'll also need this if there are any commands defined
  file { "/vagrant/bin": 
    ensure => "directory"
  }

  # a testing vhost
  apache::vhost { "precip.vm":
    docroot => "/vagrant/util",
    manage_docroot => false,
    port => '80',
    directories => [{
        path => "/vagrant/util",
        allow_override => ['All',],
    }],
    access_log => false,
        logroot => "/vagrant/log",
  }

  $parsed_siteinfo = parsejson($drupal_siteinfo)
  create_resources(drupal_vhosts, $parsed_siteinfo)
  
  # Create Drush aliases
  file { "/vagrant/vm.aliases.drushrc.php":
    content => template("precip/drush_aliases.erb"),
    replace => true,
    mode => '0644',
  }
}

define drupal_vhosts($host, $aliases = [], $path, $drupal = "7", $multisite_dir = "default", $setenv = [], $git_url = "", $git_dir = "", $commands = {}) {
  apache::vhost { "${host}":
    docroot => "/srv/www/${path}",
    manage_docroot => false,
    servername => "${host}",
    serveraliases => $aliases,
    port => '80',
    directories => [{
        path => "/srv/www/${path}",
        allow_override => ['All',],
    }],
    setenv => concat($setenv,
      [
        "AH_SITE_GROUP ${name}",
        "AH_SITE_ENVIRONMENT vm"
      ]
    ),
    access_log => false,
    logroot => "/vagrant/log",
    require => File["/vagrant/log"],
  }
  apache::vhost { "${host}-ssl":
    docroot => "/srv/www/${path}",
    manage_docroot => false,
    servername => "${host}",
    serveraliases => $aliases,
    port => '443',
    directories => [{
        path => "/srv/www/${path}",
        allow_override => ['All',],
    }],
    setenv => concat($setenv,
      [
        "AH_SITE_GROUP ${name}",
        "AH_SITE_ENVIRONMENT vm"
      ]
    ),
    access_log => false,
    logroot => "/vagrant/log",
    ssl => true,
    require => File["/vagrant/log"],
  }
  
  mysql::db { $name:
    user     => "${name}",
    password => "${name}",
    host     => 'localhost',
    grant    => ['all'],
  }
  
  mysql_user { "${name}@%":
    ensure        => 'present',
    password_hash => mysql_password("${name}"),
    subscribe    =>  Service['mysqld']
  }
  
  mysql_grant { "${name}@%/${name}.*":
    ensure     => 'present',
    options    => ['GRANT'],
    privileges => ['ALL'],
    table      => "${name}.*",
    user       => "${name}@%",
    require    => [ Mysql_database["$name"], Mysql_user["$name@%"] ],
  }
  
  if $drupal != "false" {
    file {"/srv/www/${path}/sites/${multisite_dir}":
      ensure =>'directory',
      mode => '0755',
    }

    # Ensure the tree we're going to hide settings in exists
    file {"/var/www/site-php/${name}":
      ensure => "directory",
      mode => '0755',
      require => File["/var/www/site-php"],    
    }

    # Magic Acquia-style Database Settings.
    file {"/var/www/site-php/${name}/${name}-settings.inc":
      content => template("precip/drupal_${drupal}_database.erb"),
      mode => '0644',
      subscribe => File["/var/www/site-php/${name}"],
    }
    
    # A template "local-settings.inc", in case you don't have one already
    file {"/srv/www/${path}/sites/${multisite_dir}/local-settings.inc":
      content => template("precip/drupal_${drupal}_database.erb"),
      replace => false,
      mode => '0644',
      subscribe => File["/var/www/site-php/${name}"],
    }
    
    # An Acquia-style settings.php, if you need one.
    file { "/srv/www/${path}/sites/${multisite_dir}/settings.php":
      content => template("precip/drupal_${drupal}_settings_php.erb"),
      replace => false,
      mode => '0644',
      subscribe => File["/srv/www/${path}/sites/${multisite_dir}"],
    }
  }
  
  # Let's make some shell commands!
  if empty($commands) != true {
    create_resources(command_builder, $commands)
  }
}

define command_builder($path, $cmd){
  file { "/vagrant/bin/${name}":
    content => template("precip/shell_command.erb"),
    replace => true,
    mode => '0755',
    require => File["/vagrant/bin"],
  }
}