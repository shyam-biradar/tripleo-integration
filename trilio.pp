class tripleo::profile::base::trilio (
  $step = hiera('step'),
) {

##Variables to edit
#  $NFS_SHARES="192.168.1.33:/mnt/tvault"
#  $NFS_OPTIONS=""
#  $TVAULT_APPLIANCE_IP="192.168.1.122"
#  $NOVA_CONF_FILE='/etc/nova/nova.conf'
#  $NOVA_DIST_CONF_FILE='/usr/share/nova/nova-dist.conf'
#  $NOVA_COMPUTE_FILTERS_FILE="/usr/share/nova/rootwrap/compute.filters"


## Variable declaration
  $CONTEGO_USER='nova'
  $CONTEGO_GROUP='nova'
  $CONTEGO_CONF_FILE="/etc/tvault-contego/tvault-contego.conf"
  $CONTEGO_GROUPS=['kvm','qemu','disk']
  $VAULT_DATA_DIR='/var/triliovault-mounts'
  $VAULT_DATA_DIR_OLD='/var/triliovault'
  $CONTEGO_DIR='/home/tvault'
  $CONTEGO_VIRTENV_DIR="${CONTEGO_DIR}/.virtenv"
  $LOG_DIR="/var/log/nova"
  $CONTEGO_BIN="${CONTEGO_VIRTENV_DIR}/bin/tvault-contego"
  $CONTEGO_PYTHON="${CONTEGO_VIRTENV_DIR}/bin/python"
  $CONFIG_FILES="--config-file=${NOVA_DIST_CONF_FILE} --config-file=${NOVA_CONF_FILE} --config-file=${CONTEGO_CONF_FILE}"

  if $step >= 5 {

    $LOG_ROTATE_FILE_CONTENT="/var/log/nova/tvault-contego.log {
daily
missingok
notifempty
copytruncate
size=25M
rotate 3
compress
}"


    $CONTEGO_SYSTEMD_FILE_CONTENT="[Unit]
Description=Tvault contego
After=openstack-nova-compute.service
[Service]
User=${CONTEGO_USER}
Group=${CONTEGO_GROUP}
Type=simple
ExecStart=${CONTEGO_PYTHON} ${CONTEGO_BIN} ${CONFIG_FILES}
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
"


#    $CONTEGO_CONF_FILE_CONTENT="[DEFAULT]
#vault_storage_nfs_export = ${NFS_SHARES}
#vault_storage_nfs_options = ${NFS_OPTIONS}
#vault_storage_type = nfs
#vault_data_directory_old = /var/triliovault
#vault_data_directory = /var/triliovault-mounts
#log_file = /var/log/nova/tvault-contego.log
#debug = False
#verbose = True
#max_uploads_pending = 3
#max_commit_pending = 3
#"

## Adding passwordless sudo access to 'nova' user
    file { '/etc/sudoers':
      ensure => present,
    }->
    file_line { 'Adding passwordless sudo access to nova user':
      path => '/etc/sudoers',  
      line => "${CONTEGO_USER} ALL=(ALL) NOPASSWD: ALL",
    }
 
## Adding nova user to system groups 
    user { 'Add_nova_user_to_system_groups':
       name => $CONTEGO_USER,
       ensure => present,
       gid => $CONTEGO_GROUP,
       groups => $CONTEGO_GROUPS,
    }     

##Add code to check if contego is latest, if it's not then clean existing contego

   #TODO: Copy shell script on remote node
    file { "Delete_status_file":
        path => "/tmp/trilio-update-status",
        ensure => absent,
    }

   #Install datamover
    exec { 'install_upgrade_datamover':
      command => "./contego_install.sh ${CONTEGO_DIR} ${TVAULT_APPLIANCE_IP} ${TVAULT_CONTEGO_VERSION} > /tmp/contego_install.log",
      cwd     => '/tmp/',
      provider => shell,
      path    => ['/bin/bash','/bin/','/usr/bin', '/usr/sbin',],
    }
  
    file { 'ensure_contego_log_directory':
      path => $LOG_DIR,
      ensure => 'directory',
      owner  => $CONTEGO_USER,
      group  => $CONTEGO_GROUP,
    }
    file { 'contego_directory_ownership':
      path => $CONTEGO_DIR,
      ensure => 'directory',
      owner  => $CONTEGO_USER,
      group  => $CONTEGO_GROUP,
    }
    file { 'ensure_compute_filters_file_path':
      path => "${NOVA_COMPUTE_FILTERS_FILE}",
      ensure => present,
    }->
    file_line { "Append_line":
      path => "${NOVA_COMPUTE_FILTERS_FILE}",  
      line => "rm: CommandFilter, rm, root",
    }
    file { 'ensure_etc_contego_dir':
      path => '/etc/tvault-contego',
      ensure => 'directory',
    }->
    file { "ensure_contego_conf_file":
      path => "${CONTEGO_CONF_FILE}",
      ensure => present,
      content => "${CONTEGO_CONF_FILE_CONTENT}",
    }
 
    file { 'ensure_log_roatate_config_file':
      path => '/etc/logrotate.d/tvault-contego',
      content => $LOG_ROTATE_FILE_CONTENT,
    }
    file { 'ensure_contego_systemd_file':
      path => '/etc/systemd/system/tvault-contego.service',
      content => $CONTEGO_SYSTEMD_FILE_CONTENT,
    }~>
    exec {'daemon_reload_for_contego':
      cwd => '/tmp',
      command => 'systemctl daemon-reload',
      path => ['/usr/bin', '/usr/sbin',],
      refreshonly => true, 
    }
    service { 'ensure_contego_service_running':
      name => 'tvault-contego',
      enable => true,
      ensure => 'running',
      require => [Exec['daemon_reload_for_contego'],Exec['install_upgrade_datamover']],
      subscribe => File['ensure_contego_systemd_file'],
    }
   
  }

}


class { 'tripleo::profile::base::trilio':
         step => 6,
      }

