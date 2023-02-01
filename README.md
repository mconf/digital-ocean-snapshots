# Digital Ocean Snapshots

A simple way to automate snapshots for droplets and volumes on DigitalOcean.

## How it works

* Add your API key to the script (set it on `API_TOKEN`).
* Set the script to run on cron daily (or weekly, or wherever you want).
* Add the `snap` tag (or choose another tag setting `TAG`) on the droplets and volumes you want to snapshot.
* The script will run, create the new snapshots and rotate (remove old snapshots). It will keep `NUM_SNAPSHOTS` snapshots of each droplet and volume.

## Running

```
DRYRUN=true TAG=snap NUM_SNAPSHOTS=5 API_TOKEN=adigitaloceansecrettoken ruby do-snap.rb
```


## Running on cron

```
# run once a day at 4AM UTC
0 4 * * * docker run -d --name snap -e API_TOKEN=XXX mconf/digital-ocean-snapshots:latest
```

## Development


### Running on docker

```
docker build . -t mconf/digital-ocean-snapshots:latest
docker run -ti --rm --name snap -e API_TOKEN=XXX mconf/digital-ocean-snapshots:latest
```

### Generating a new version

Just create and push a tag and dockerhub will build a new image.
