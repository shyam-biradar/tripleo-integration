class trilio (
  $contego_user				= 'nova',
  $contego_group			= 'nova',
  $contego_conf_file			= "/etc/tvault-contego/tvault-contego.conf",
  $contego_groups			= ['kvm','qemu','disk'],
  $vault_data_dir			= '/var/triliovault-mounts',
  $vault_data_dir_old			= '/var/triliovault',
  $contego_dir				= '/home/tvault',
  $contego_virtenv_dir			= '${contego_dir}/.virtenv',
  $log_dir				= '/var/log/nova',
  $contego_bin				= '${contego_virtenv_dir}/bin/tvault-contego',
  $contego_python			= '${contego_virtenv_dir}/bin/python',
  $config_files				= '--config-file=${nova_dist_conf_file} --config-file=${nova_conf_file} --config-file=${contego_conf_file}',
  $nova_conf_file			= '/etc/nova/nova.conf',
  $nova_dist_conf_file			= '/usr/share/nova/nova-dist.conf',
  $nova_compute_filters_file		= '/usr/share/nova/rootwrap/compute.filters',
  $nfs_shares				= '192.168.1.33:/mnt/tvault',
  $nfs_options				= '',
  $tvault_appliance_ip			= '192.168.1.122',
  $log_rotate_file_content		= "/var/log/nova/tvault-contego.log {
daily
missingok
notifempty
copytruncate
size=25M
rotate 3
compress
}",
  $contengo_systemd_file_content	= "[Unit]
Description=Tvault contego
After=openstack-nova-compute.service
[Service]
User=nova
Group=nova
Type=simple
ExecStart=/home/tvault/.virtenv/bin/python /home/tvault/.virtenv/bin/tvault-contego --config-file=/usr/share/nova/nova-dist.conf --config-file=/etc/nova/nova.conf --config-file=/etc/tvault-contego/tvault-contego.conf
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
",
  $contego_conf_file_content		= "[DEFAULT]
vault_storage_nfs_export = 192.168.1.33:/mnt/tvault
vault_storage_nfs_options = 
vault_storage_type = nfs
vault_data_directory_old = /var/triliovault
vault_data_directory = /var/triliovault-mounts
log_file = /var/log/nova/tvault-contego.log
debug = False
verbose = True
max_uploads_pending = 3
max_commit_pending = 3
",
) {
## Adding passwordless sudo access to 'nova' user
    file { "/etc/sudoers.d/${contego_user}":
      ensure => present,
    }->
    file_line { 'Adding passwordless sudo access to nova user':
      path => "/etc/sudoers.d/${contego_user}",
      line => "${contego_user} ALL=(ALL) NOPASSWD: ALL",
    }

## Adding nova user to system groups 
    user { 'Add_nova_user_to_system_groups':
       name => $contego_user,
       ensure => present,
       gid => $contego_group,
       groups => $contego_groups,
    }     

##Add code to check if contego is latest, if it's not then clean existing contego

   #TODO: Copy shell script on remote node
    file { "Delete_status_file":
        path => "/tmp/trilio-update-status",
        ensure => absent,
    }

   #Install datamover
    exec { 'install_upgrade_datamover':
      command => "./contego_install.sh ${contego_dir} ${tvault_appliance_ip} > /tmp/contego_install.log",
      provider => shell,
      path    => ['/bin/bash','/bin/','/usr/bin', '/usr/sbin',],
    }
  
    file { 'ensure_contego_log_directory':
      path => $log_dir,
      ensure => 'directory',
      owner  => $contego_user,
      group  => $contego_group,
    }
    file { 'contego_directory_ownership':
      path => $contego_dir,
      ensure => 'directory',
      owner  => $contego_user,
      group  => $contego_group,
    }
    file { 'ensure_compute_filters_file_path':
      path => "${nova_compute_filters_file}",
      ensure => present,
    }->
    file_line { "Append_line":
      path => "${nova_compute_filters_file}",  
      line => "rm: CommandFilter, rm, root",
    }
    file { 'ensure_etc_contego_dir':
      path => '/etc/tvault-contego',
      ensure => 'directory',
    }->
    file { "ensure_contego_conf_file":
      path => "${contego_conf_file}",
      ensure => present,
      content => "${contego_conf_file_content}",
    }
 
    file { 'ensure_log_roatate_config_file':
      path => '/etc/logrotate.d/tvault-contego',
      content => $log_rotate_file_content,
    }
    file { 'ensure_contego_systemd_file':
      path => '/etc/systemd/system/tvault-contego.service',
      content => $contengo_systemd_file_content,
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

class { 'trilio': }
