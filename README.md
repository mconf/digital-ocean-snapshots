# Digital Ocean Snapshots

A simple way to automate snapshots for droplets and volumes on DigitalOcean.

## How it works

* Add your API key to the script (set it on `API_TOKEN`).
* Set the script to run on cron daily (or weekly, or wherever you want).
* Add the `snap` tag on the droplets and volumes you want to snapshot.
* The script will run, create the new snapshots and rotate (remove old snapshots).

### Running on cron

```
# run once a day at 4AM UTC
0 4 * * * docker run -d --name snap -e API_TOKEN=XXX mconf/digital-ocean-snapshots:latest
```

## TODO

- [x] Configurations via environment variables
- [x] Snapshots for volumes
- [x] Pack it all to run with docker
- [ ] Create a better structure so we do not need global variables
