#!/usr/bin/env ruby

# Cron example:
# 0 4 * * * docker run -d --name snap -e API_TOKEN=XXX -e TAG=snap mconf/digital-ocean-snapshots:latest

require 'droplet_kit'
require 'logger'

API_TOKEN = ENV.fetch('API_TOKEN')
NUM_SNAPSHOTS = ENV.fetch('NUM_SNAPSHOTS', 3).to_i # will keep this number of snaps
TAG = ENV.fetch('TAG', 'snap') # snapshot all droplets with this tag

client = DropletKit::Client.new(access_token: API_TOKEN)
$logger = Logger.new(STDOUT)

def snapshot_name(obj)
  "auto-#{obj.name}-#{Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")}"
end

def snapshot_name_matcher
  # TODO: change to this regex after all `auto-<timestamp>` snaps were removed
  # /^auto-[\d]{4}*-[\d]{2}-[\d]{2}T[\d]{2}:[\d]{2}:[\d]{2}Z/
  /^auto-.*/
end

def create_snapshot(client, droplet)
  name = snapshot_name(droplet)
  $logger.info "  Creating droplet snapshot #{name}..."
  begin
    client.droplet_actions.snapshot(droplet_id: droplet.id, name: name)
  rescue DropletKit::FailedCreate => e
    $logger.error "    Failed to create snapshot: #{e.inspect}"
  end

  droplet.volume_ids.each do |volume_id|
    volume = client.volumes.find(id: volume_id)
    name = snapshot_name(volume)
    $logger.info "  Creating volume snapshot #{name}..."
    begin
      client.volumes.create_snapshot(id: volume_id, name: name)
    rescue DropletKit::FailedCreate => e
      $logger.error "    Failed to create snapshot: #{e.inspect}"
    end
  end
end

def cleanup_helper(client, snapshots)
  snapshots = snapshots.select { |snap|
    snap.name.match(snapshot_name_matcher)
  }.sort_by { |snap|
    Time.parse(snap.created_at).to_i
  }

  if snapshots.count > 0
    $logger.info "    Found snapshots: #{snapshots.map(&:name)}"
    if snapshots.count > NUM_SNAPSHOTS
      $logger.info "    Will remove old snapshots (limit: #{NUM_SNAPSHOTS})"
      remove_count = snapshots.count - NUM_SNAPSHOTS
      to_remove = snapshots.first(remove_count)
      to_remove.each do |snap|
        $logger.info "      Removing #{snap.name}..."
        client.snapshots.delete(id: snap.id)
      end
    else
      $logger.info "    Will not remove any snapshot (limit: #{NUM_SNAPSHOTS})"
    end
  else
    $logger.info '    No automatic snapshots found'
  end
end

def cleanup(client, droplet)
  $logger.info "  Cleaning up #{droplet.name}..."
  snapshots = client.droplets.snapshots(id: droplet.id)
  cleanup_helper(client, snapshots)

  droplet.volume_ids.each do |volume_id|
    volume = client.volumes.find(id: volume_id)
    $logger.info "  Cleaning up #{volume.name}..."
    snapshots = client.volumes.snapshots(id: volume_id)
    cleanup_helper(client, snapshots)
  end
end

client.droplets.all.each do |droplet|
  if droplet.tags.include?(TAG)
    $logger.info "Backing up: #{droplet.name} (#{droplet.id})"
    create_snapshot(client, droplet)
    cleanup(client, droplet)
  else
    $logger.debug "Skipping: #{droplet.name} (#{droplet.id})"
  end
end
