class graphite {

  $build_dir = "/tmp"

  $graphite_version = "0.9.13-pre1"
  $webapp_url = "https://github.com/graphite-project/graphite-web/archive/$graphite_version.tar.gz"
  $webapp_loc = "$build_dir/graphite-web.tar.gz"

  $whisper_version = "0.9.13-pre1"
  $whisper_url = "https://github.com/graphite-project/whisper/archive/$whisper_version.tar.gz"
  $whisper_loc = "$build_dir/whisper.tar.gz"

  include elasticsearch
  include grafana

  exec { "download-graphite-webapp":
    command => "wget -O $webapp_loc $webapp_url",
    creates => "$webapp_loc"
  }

  exec { "unpack-webapp":
    command => "tar -zxvf $webapp_loc",
    cwd => $build_dir,
    subscribe=> Exec[download-graphite-webapp],
    refreshonly => true,
  }

  exec { "install-webapp":
    command => "python setup.py install",
    cwd => "$build_dir/graphite-web-$graphite_version",
    require => Exec[unpack-webapp],
    creates => "/opt/graphite/webapp"
  }

  exec { "download-whisper":
    command => "wget -O $whisper_loc $whisper_url",
    creates => "$whisper_loc"
  }

  exec { "unpack-whisper":
    command => "tar -zxvf $whisper_loc",
    cwd => $build_dir,
    subscribe=> Exec[download-whisper],
    refreshonly => true,
  }

  exec { "install-whisper":
    command => "python setup.py install",
    cwd => "$build_dir/whisper-$whisper_version",
    require => Exec[unpack-whisper]
  }

  file { [ "/opt/graphite/storage", "/opt/graphite/storage/whisper" ]:
    owner => "www-data",
    subscribe => Exec["install-webapp"],
    mode => "0775",
  }

  exec { "init-db":
    command => "python manage.py syncdb --noinput",
    cwd => "/opt/graphite/webapp/graphite",
    creates => "/opt/graphite/storage/graphite.db",
    subscribe => File["/opt/graphite/storage"],
    require => [ File["/opt/graphite/webapp/graphite/initial_data.json"], Package["python-django-tagging"] ]
  }

  file { "/opt/graphite/webapp/graphite/initial_data.json" :
    require => File["/opt/graphite/storage"],
    ensure => present,
    content => '
[
  {
    "pk": 1, 
    "model": "auth.user", 
    "fields": {
      "username": "admin", 
      "first_name": "", 
      "last_name": "", 
      "is_active": true, 
      "is_superuser": true, 
      "is_staff": true, 
      "last_login": "2011-09-20 17:02:14", 
      "groups": [], 
      "user_permissions": [], 
      "password": "sha1$1b11b$edeb0a67a9622f1f2cfeabf9188a711f5ac7d236", 
      "email": "root@example.com", 
      "date_joined": "2011-09-20 17:02:14"
    }
  }
]'
  }

  file { "/opt/graphite/storage/graphite.db" :
    owner => "www-data",
    mode => "0664",
    subscribe => Exec["init-db"],
    notify => Service["apache2"],
  }

  file { "/opt/graphite/storage/log/webapp/":
    ensure => "directory",
    owner => "www-data",
    mode => "0775",
    subscribe => Exec["install-webapp"],
  }

  file { "/opt/graphite/webapp/graphite/local_settings.py" :
    source => "puppet:///modules/graphite/local_settings.py",
    ensure => present,
    require => File["/opt/graphite/storage"]
  }

  file { "/opt/graphite/conf/graphite.wsgi" :
    source => "puppet:///modules/graphite/graphite.wsgi",
    ensure => present,
    require => File["/opt/graphite/storage"]
  }

  file { "/etc/apache2/sites-available/000-default.conf" :
    source => "puppet:///modules/graphite/000-default.conf",
    ensure => present,
    notify => Service["apache2"],
    require => Package["apache2"],
  }

  service { "apache2" :
    ensure => "running",
    require => [ File["/opt/graphite/storage/log/webapp/"], File["/opt/graphite/storage/graphite.db"], Package["libapache2-mod-wsgi"] ],
  }

  package {
    [ apache2, libapache2-mod-wsgi, htop, python-ldap, python-cairo, python-django, python-django-tagging, python-simplejson, libapache2-mod-python, python-memcache, python-pysqlite2]: ensure => latest;
  }
}
