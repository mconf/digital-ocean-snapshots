#!/usr/bin/env ruby

# Requires:
# - ruby 2.3
# - gem droplet_kit
#
# Cron example:
# 0 4 * * * /home/user/do-snap.rb >> /home/user/do-snap.log 2>&1

require 'droplet_kit'

API_TOKEN = 'my-secret-digital-ocean-key'
NUM_SNAPSHOTS = 3  # will keep this or +1 snaps
TAG = 'snap'       # snapshot all droplets with this tag

client = DropletKit::Client.new(access_token: API_TOKEN)

def snapshot_name(obj)
  "auto-#{obj.name}-#{Time.now.to_i}"
end

def snapshot_name_matcher
  /^auto-.*[0-9]{10}$/
end

def create_snapshot(client, droplet)
  name = snapshot_name(droplet)
  puts "  Creating droplet snapshot #{name}..."
  begin
    client.droplet_actions.snapshot(droplet_id: droplet.id, name: name)
  rescue DropletKit::FailedCreate => e
    puts "    ERROR: failed to create snapshot: #{e.inspect}"
  end

  droplet.volume_ids.each do |volume_id|
    volume = client.volumes.find(id: volume_id)
    name = snapshot_name(volume)
    puts "  Creating volume snapshot #{name}..."
    begin
      client.volumes.create_snapshot(id: volume_id, name: name)
    rescue DropletKit::FailedCreate => e
      puts "    ERROR: failed to create snapshot: #{e.inspect}"
    end
  end
end

def cleanup(client, droplet)
  puts "  Cleaning up #{droplet.name}..."
  snapshots = client.droplets.snapshots(id: droplet.id)
  snapshots = snapshots.select { |snap| snap.name.match(snapshot_name_matcher) }

  if snapshots.count > 0
    puts "    Found droplet snapshots: #{snapshots.map(&:name)}"
    if snapshots.count > NUM_SNAPSHOTS
      puts "    Will remove old snapshots (limit: #{NUM_SNAPSHOTS})"
      remove_count = snapshots.count - NUM_SNAPSHOTS
      to_remove = snapshots.sort.first(remove_count)
      to_remove.each do |snap|
        puts "      Removing #{snap.name}..."
        client.snapshots.delete(id: snap.id)
      end
    else
      puts "    Will not remove any snapshot (limit: #{NUM_SNAPSHOTS})"
    end
  else
    puts '    No automatic snapshots found'
  end

  droplet.volume_ids.each do |volume_id|
    volume = client.volumes.find(id: volume_id)
    puts "  Cleaning up #{volume.name}..."
    snapshots = client.volumes.snapshots(id: volume_id)
    snapshots = snapshots.select { |snap| snap.name.match(snapshot_name_matcher) }

    if snapshots.count > 0
      puts "    Found volume snapshots: #{snapshots.map(&:name)}"
      if snapshots.count > NUM_SNAPSHOTS
        puts "    Will remove old snapshots (limit: #{NUM_SNAPSHOTS})"
        remove_count = snapshots.count - NUM_SNAPSHOTS
        to_remove = snapshots.sort.first(remove_count)
        to_remove.each do |snap|
          puts "      Removing #{snap.name}..."
          client.snapshots.delete(id: snap.id)
        end
      else
        puts "    Will not remove any snapshot (limit: #{NUM_SNAPSHOTS})"
      end
    else
      puts '    No automatic snapshots found'
    end
  end
end

client.droplets.all.each do |droplet|
  if droplet.tags.include?(TAG)
    puts "Backing up: #{droplet.name} (#{droplet.id})"
    create_snapshot(client, droplet)
    cleanup(client, droplet)
  else
    puts "Skipping: #{droplet.name} (#{droplet.id})"
  end
end
