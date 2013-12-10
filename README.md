rubyocean
=========

rubyocean is a command line tool, written in ruby, that allows the user to interact with their droplets via the DigitalOcean API. Currently this tool allows for the creation/viewing/rebooting of Droplets (DigitalOcean terminology for servers), as well as creation/viewing of DNS information. Other data related to these operation, such as available regions, images, SSH keys, and sizes is also available.

This tool assumes you have the following:
* A DigitalOcean API Key
* A DigitalOcean Client ID
* Ruby 1.8.3+
* Bundler
* Possibly a unixlike environment (it will probably work on Windows, but I haven't tested it)


Getting started
--------------

Ensure you have all the needed gems installed (from the directory you cloned rubyocean to):

```sh
bundle install
```

Create the config file:
```sh
./rubyocean.rb --create-config --client-id YOUR_CLIENT_ID --api-key YOUR_API_KEY
```

Test by listing your droplets:
```sh
./rubyocean.rb -l
```

View all available options:
```sh
./rubyocean.rb -h
Usage: rubyocean.rb [options]

Specific options:
    -l, --list-droplets              List droplets
    -v, --verbose                    Run verbosely
    -r, --reboot DROPLET_ID          Reboot droplet
    -s, --sizes                      Droplet Sizes
    -k, --ssh-keys                   List SSH Keys
    -g, --regions                    List available droplet regions
    -i, --images                     List available droplet images
        --get-domains                Get Domain data
        --view-domain DOMAIN_ID      View data for specific Domain ID
        --create-domain-record       Create a new domain record
        --record-type DOMAIN_RECORD_TYPE
                                     The type of domain record to create: A, CNAME, NS, TXT, MX, SRV
        --record-data DOMAIN_RECORD_DATA
                                     Value of the record
        --record-name DOMAIN_RECORD_NAME
                                     Name, required for A, CNAME, TXT, SRV
        --domain-id DOMAIN_ID        Modify for specific Domain ID
    -c, --create-droplet             Create a new droplet
        --droplet-name DROPLET_NAME  Name (hostname) of the droplet
        --droplet-size DROPLET_SIZE  Size ID of the droplet (view available with -s)
        --droplet-image DROPLET_IMAGE
                                     Image ID to use for the droplet
        --droplet-region DROPLET_REGION
                                     Region ID of where to create the droplet (view available with -g)
        --droplet-keys DROPLET_KEYS  SSH keys to add to the droplet root account (if using multiple delimitate with a comma and no space)
        --create-config              Create a config file containing your API Key and Client ID (will write to ~/.rubyocean)
        --client-id CLIENT_ID        Specify your Client ID which will be written to the config file
        --api-key API_KEY            Specify your API Key which will be written to the config file
    -h, --help                       Show this message
```


Planned Changes
----------
* Removal of droplets/DNS (not included at the moment due to the destructive nature)
* Cleanup of code
