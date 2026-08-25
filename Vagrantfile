NODE_ROLES = ["node2", "node3", "node4"]
NODE_BOXES = ["local/debian13-root", "local/debian13-root", "local/debian13-root"]
NODE_IPS = ["192.168.56.10", "192.168.56.11", "192.168.56.12"]
NODE_CPUS = 2
NODE_MEMORY = 2048

def provision(vm, role, node_num)
  vm.box = NODE_BOXES[node_num]
  vm.hostname = role
  vm.network "private_network", ip: NODE_IPS[node_num]

  vm.provider :libvirt do |libvirt|
    libvirt.memory = NODE_MEMORY
    libvirt.cpus = NODE_CPUS
  end
end

Vagrant.configure("2") do |config|
  config.ssh.username = "root"
  config.ssh.private_key_path = File.expand_path("~/.ssh/id_ed25519")
  config.ssh.insert_key = false

  config.vm.synced_folder ".", "/vagrant", disabled: true

  NODE_ROLES.each_with_index do |name, i|
    config.vm.define name do |node|
      provision(node.vm, name, i)
    end
  end
end
