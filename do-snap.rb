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

# if the last snapshot is not older than this number of hours, won't back it up (nor remove old snaps)
# protection in case the script runs too many times in a short period of time and ends up removing
# snapshots that are not that old
THRESHOLD_HOURS = ENV.fetch('THRESHOLD_HOURS', 23).to_i

class DOSnap
  def initialize(api_token, num_snapshots, tag, threshold_h = 23, dryrun=true)
    @num_snapshots = num_snapshots
    @tag = tag
    @dryrun = dryrun
    @client = DropletKit::Client.new(access_token: api_token)
    @threshold_h = threshold_h

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
    /^auto-.*[\d]{4}-[\d]{2}-[\d]{2}T[\d]{2}:[\d]{2}:[\d]{2}Z/i
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

  def cleanup(droplet, snapshots)
    @logger.info "#{resource_log_id(droplet)} Cleaning up..."
    cleanup_helper(snapshots, droplet)

    droplet.volume_ids.each do |volume_id|
      volume = @client.volumes.find(id: volume_id)
      @logger.info "#{resource_log_id(volume)} Cleaning up..."
      snapshots = ordered_snapshots(volume, :volume)
      cleanup_helper(snapshots, volume)
    end
  end

  def resource_log_id(resource)
    "[#{resource.name}] [#{resource.id}]"
  end

  def should_back_up(droplet, droplet_snapshots)
    last = Time.parse(droplet_snapshots.last.created_at)
    threshold = Time.now.utc - (@threshold_h * 60 * 60)
    now = Time.now.utc
    if last < threshold
      @logger.info "#{resource_log_id(droplet)} Last snapshot is '#{last}', which is older than " \
                   "the threshold '#{threshold}' (now '#{now}')"
      true
    else
      @logger.info "#{resource_log_id(droplet)} Last snapshot is '#{last}', which is NOT older than " \
                   "the threshold '#{threshold}' (now '#{now}')"
      false
    end
  end

  def ordered_snapshots(resource, type = :droplet)
    if type == :volume
      snapshots = @client.volumes.snapshots(id: resource.id)
    else
      snapshots = @client.droplets.snapshots(id: resource.id)
    end
    snapshots.select { |snap|
      snap.name.match(snapshot_name_matcher)
    }.sort_by { |snap|
      Time.parse(snap.created_at).to_i
    }
  end

  def run
    @client.droplets.all.each do |droplet|
      if droplet.tags.include?(@tag)
        @logger.info "#{resource_log_id(droplet)} Checking"
        droplet_snapshots = ordered_snapshots(droplet)
        if should_back_up(droplet, droplet_snapshots)
          @logger.info "#{resource_log_id(droplet)} Backing it up"
          create_snapshot(droplet)
          cleanup(droplet, droplet_snapshots)
        else
          @logger.info "#{resource_log_id(droplet)} Will not back it up"
        end

      else
        @logger.debug "#{resource_log_id(droplet)} Skipping, no tag '#{@tag}' found"
      end
    end
  end
end

do_snap = DOSnap.new(API_TOKEN, NUM_SNAPSHOTS, TAG, THRESHOLD_HOURS, DRYRUN)
do_snap.run
