#!/usr/bin/env ruby

# Cron example:
# 0 4 * * * docker run -d --name snap -e API_TOKEN=XXX -e TAG=snap DRYRUN=false mconf/digital-ocean-snapshots:latest

require 'droplet_kit'
require 'logger'
require 'json'

API_TOKEN = ENV.fetch('API_TOKEN')

# will keep this number of snapshots for each droplet or volume
NUM_SNAPSHOTS = ENV.fetch('NUM_SNAPSHOTS', 3).to_i

# snapshot all droplets with this tag
TAG = ENV.fetch('TAG', 'snap')

# default to true, setting to 'false' (case insensitive) turns it off
DRYRUN = !ENV.fetch('DRYRUN', 'true').match(/false/i)

class DOSnap
  def initialize(api_token, num_snapshots, tag, dryrun=true)
    @num_snapshots = num_snapshots
    @tag = tag
    @dryrun = dryrun
    @client = DropletKit::Client.new(access_token: api_token)

    @logger = Logger.new(STDOUT)
    @logger.formatter = proc do |severity, datetime, progname, msg|
      JSON.dump(timestamp: "#{datetime.to_s}", message: msg) + $/
    end
    @logger.info "Running in DRYRUN mode" if @dryrun
  end

  def snapshot_name(obj)
    "auto-#{obj.name}-#{Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")}"
  end

  def snapshot_name_matcher
    # TODO: change to this regex after all `auto-<timestamp>` snaps were removed
    # /^auto-[\d]{4}*-[\d]{2}-[\d]{2}T[\d]{2}:[\d]{2}:[\d]{2}Z/
    /^auto-.*/
  end

  def create_snapshot(droplet)
    name = snapshot_name(droplet)
    @logger.info "#{resource_log_id(droplet)} Creating droplet snapshot #{name}..."
    begin
      @client.droplet_actions.snapshot(droplet_id: droplet.id, name: name) unless @dryrun
    rescue DropletKit::FailedCreate => e
      @logger.error "#{resource_log_id(droplet)} Failed to create snapshot: #{e.inspect}"
    end

    droplet.volume_ids.each do |volume_id|
      volume = @client.volumes.find(id: volume_id)
      name = snapshot_name(volume)
      @logger.info "#{resource_log_id(droplet)} Creating volume snapshot #{name}..."
      begin
        @client.volumes.create_snapshot(id: volume_id, name: name) unless @dryrun
      rescue DropletKit::FailedCreate => e
        @logger.error "#{resource_log_id(droplet)} Failed to create snapshot: #{e.inspect}"
      end
    end
  end

  def cleanup_helper(snapshots, parent)
    snapshots = snapshots.select { |snap|
      snap.name.match(snapshot_name_matcher)
    }.sort_by { |snap|
      Time.parse(snap.created_at).to_i
    }

    if snapshots.count > 0
      @logger.info "#{resource_log_id(parent)} Found snapshots: #{snapshots.map(&:name).join(', ')}"
      if snapshots.count > NUM_SNAPSHOTS
        @logger.info "#{resource_log_id(parent)} Will remove old snapshots (limit: #{NUM_SNAPSHOTS})"
        remove_count = snapshots.count - NUM_SNAPSHOTS
        to_remove = snapshots.first(remove_count)
        to_remove.each do |snap|
          @logger.info "#{resource_log_id(parent)} Removing #{snap.name}..."
          @client.snapshots.delete(id: snap.id) unless @dryrun
        end
      else
        @logger.info "#{resource_log_id(parent)} Will not remove any snapshot (limit: #{NUM_SNAPSHOTS})"
      end
    else
      @logger.info "#{resource_log_id(parent)} No automatic snapshots found"
    end
  end

  def cleanup(droplet)
    @logger.info "#{resource_log_id(droplet)} Cleaning up..."
    snapshots = @client.droplets.snapshots(id: droplet.id)
    cleanup_helper(snapshots, droplet)

    droplet.volume_ids.each do |volume_id|
      volume = @client.volumes.find(id: volume_id)
      @logger.info "#{resource_log_id(volume)} Cleaning up..."
      snapshots = @client.volumes.snapshots(id: volume_id)
      cleanup_helper(snapshots, volume)
    end
  end

  def resource_log_id(resource)
    "[#{resource.name}] [#{resource.id}]"
  end

  def run
    @client.droplets.all.each do |droplet|
      if droplet.tags.include?(TAG)
        @logger.info "#{resource_log_id(droplet)} Backing up"
        create_snapshot(droplet)
        cleanup(droplet)
      else
        @logger.debug "#{resource_log_id(droplet)} Skipping"
      end
    end
  end
end

do_snap = DOSnap.new(API_TOKEN, NUM_SNAPSHOTS, TAG, DRYRUN)
do_snap.run
