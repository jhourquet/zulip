# Minimal shared configuration needed to run a Zulip PostgreSQL database.
class zulip::postgresql_base {
  include zulip::postgresql_common
  include zulip::process_fts_updates

  case $::osfamily {
    'debian': {
      $postgresql = "postgresql-${zulip::postgresql_common::version}"
      $postgres_sharedir = "/usr/share/postgresql/${zulip::postgresql_common::version}"
      $postgres_confdirs = [
        "/etc/postgresql/${zulip::postgresql_common::version}",
        "/etc/postgresql/${zulip::postgresql_common::version}/main",
      ]
      $postgres_confdir = $postgres_confdirs[-1]
      $postgres_datadir = "/var/lib/postgresql/${zulip::postgresql_common::version}/main"
      $tsearch_datadir = "${postgres_sharedir}/tsearch_data"
      $pgroonga_setup_sql_path = "${postgres_sharedir}/pgroonga_setup.sql"
      $setup_system_deps = 'setup_apt_repo'
      $postgres_restart = "pg_ctlcluster ${zulip::postgresql_common::version} main restart"
      $postgres_dict_dict = '/var/cache/postgresql/dicts/en_us.dict'
      $postgres_dict_affix = '/var/cache/postgresql/dicts/en_us.affix'
    }
    'redhat': {
      $postgresql = "postgresql${zulip::postgresql_common::version}"
      $postgres_sharedir = "/usr/pgsql-${zulip::postgresql_common::version}/share"
      $postgres_confdirs = [
        "/var/lib/pgsql/${zulip::postgresql_common::version}",
        "/var/lib/pgsql/${zulip::postgresql_common::version}/data",
      ]
      $postgres_confdir = $postgres_confdirs[-1]
      $postgres_datadir = "/var/lib/pgsql/${zulip::postgresql_common::version}/data"
      $tsearch_datadir = "${postgres_sharedir}/tsearch_data/"
      $pgroonga_setup_sql_path = "${postgres_sharedir}/pgroonga_setup.sql"
      $setup_system_deps = 'setup_yum_repo'
      $postgres_restart = "systemctl restart postgresql-${zulip::postgresql_common::version}"
      # TODO Since we can't find the Postgres dicts directory on CentOS yet, we
      # link directly to the hunspell directory.
      $postgres_dict_dict = '/usr/share/myspell/en_US.dic'
      $postgres_dict_affix = '/usr/share/myspell/en_US.aff'
    }
    default: {
      fail('osfamily not supported')
    }
  }

  file { "${tsearch_datadir}/en_us.dict":
    ensure  => 'link',
    require => Package[$postgresql],
    target  => $postgres_dict_dict,
  }
  file { "${tsearch_datadir}/en_us.affix":
    ensure  => 'link',
    require => Package[$postgresql],
    target  => $postgres_dict_affix,

  }
  file { "${tsearch_datadir}/zulip_english.stop":
    ensure  => file,
    require => Package[$postgresql],
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => 'puppet:///modules/zulip/postgresql/zulip_english.stop',
  }
  file { "${zulip::common::nagios_plugins_dir}/zulip_postgres_appdb":
    require => Package[$zulip::common::nagios_plugins],
    recurse => true,
    purge   => true,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    source  => 'puppet:///modules/zulip/nagios_plugins/zulip_postgres_appdb',
  }

  $pgroonga = zulipconf('machine', 'pgroonga', '')
  if $pgroonga == 'enabled' {
    # Needed for optional our full text search system
    package{"${postgresql}-pgroonga":
      ensure  => 'installed',
      require => [Package[$postgresql],
                  Exec[$setup_system_deps]],
    }

    file { $pgroonga_setup_sql_path:
      ensure  => file,
      require => Package["${postgresql}-pgroonga"],
      owner   => 'postgres',
      group   => 'postgres',
      mode    => '0640',
      source  => 'puppet:///modules/zulip/postgresql/pgroonga_setup.sql',
    }

    exec{'create_pgroonga_extension':
      require => File[$pgroonga_setup_sql_path],
      # lint:ignore:140chars
      command => "bash -c 'cat ${pgroonga_setup_sql_path} | su postgres -c \"psql -v ON_ERROR_STOP=1 zulip\" && touch ${pgroonga_setup_sql_path}.applied'",
      # lint:endignore
      creates => "${pgroonga_setup_sql_path}.applied",
    }
  }

  $s3_backups_key        = zulipsecret('secrets', 's3_backups_key', '')
  $s3_backups_secret_key = zulipsecret('secrets', 's3_backups_secret_key', '')
  $s3_backups_bucket     = zulipsecret('secrets', 's3_backups_bucket', '')
  if $s3_backups_key != '' and $s3_backups_secret_key != '' and $s3_backups_bucket != '' {
    include zulip::postgresql_backups
  }
}
