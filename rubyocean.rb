#!/bin/ruby
=begin
DigitalOcean command line utility made by steve morrissey <uberamd@gmail.com>

What does it do? Helps manage your digitalocean domains (DNS stuff) and droplets

What won't it do (currently)? Deletion. Removal of DNS or droplets via command line is scary because one fat fingered
droplet/domain ID could cause you to lose an entire server. This tool will assist in creation of droplets and DNS data,
but for removal I suggest use of the web interface. I am still going to code in deletion eventually, however it'll be hidden
behind a super secret command line switch due to the destructive nature :)

Why did I make this? While the web interface is slick, I need a way to easily add new droplets to my cluster. When
joining this tool with another I can create a droplet, get the IP of the system, puppetize it, then add it to the
haproxy backends without ever having to manually login to each system or touch a web interface. And the longest part of
the process is simply DNS propogation. The process goes like this:
  - Make a new droplet
  - Using the IP of the droplet add a new DNS entry
  - Use the second tool to apply needed config changes and install puppet
  - Puppet will finish up the rest of the config changes
  - Finally add the new IP to the pool of haproxy backend servers


REQUIREMENTS:
You MUST either create a config file in your home directory OR specify your API key and client ID directly in this file!
The config file is simply a file named '.rubyocean' located in your home directory that contains a single line that looks like this:
  YOUR_CLIENT_ID:YOUR_API_KEY

If you'd like to have this file automatically generated do a:
  ./rubyocean.rb --create-config --client-id YOUR_CLIENT_ID --api-key YOUR_API_KEY

The syntax of the commands... (note, use '-h' to view this)

Droplets:
-l, --list-droplets: lists your current droplets
-r, --reboot [droplet_id]: reboots a droplet when given an ID (which you get via -l)
-s, --sizes: shows the available droplet sizes
-k, --ssh-keys: lists the ssh keys tied to your account
-g, --regions: shows available regions droplets may be created in
-i, --images: lists the images that are available when creating new droplets
--create-droplet: creates a new droplet, requires the following:
  --droplet-name: the hostname of the droplet (and what it'll be identified as in the web interface)
  --droplet-size: sizing of the droplet, obtained via -s
  --droplet-image: which image to apply to the new droplet, obtained via -i
  --droplet-region: where to place the droplet on the interwebs, obtained via -g
  --droplet-keys: which ssh keys to add to the root account, obtained via -k, comma-separated with no space (123,456,789)

Example usage, Creating a new droplet: ./rubyocean.rb --create-droplet --droplet-name http4 --droplet-size 66 --droplet-image 473123 --droplet-region 4 --droplet-keys 11709

Note: These can be chained. If you want to view your droplets, and a list of regions, images, and keys simply do a:
  ./rubyocean.rb -l -g -i -k
This will make it easier to create new droplets by presenting you with all available options for the various required fields.

DNS:
--get-domains: returns a list of the domains attached to your account
--view-domain [domain_id]: displays data associated with a specific domain
--create-domain-record: creates a new DNS entry, requires the following:
  --record-type [A,CNAME,NS,TXT,MX,SRV]: the type of record you wish to create
  --record-data [data]: the value of the record
  --record-name [name]: the name given to the record, needed for A, CNAME, TXT, SRV
  --domain-id [domain_id]: the domain to create the DNS record on, as obtained via --get-domains

Example usage, Creating an A entry: ./rubyocean.rb --create-domain-record --domain-id 47188 --record-type A --record-name dev --record-data 192.241.245.76
Example usage, Creating a CNAME entry (test.example.com): ./rubyocean.rb --create-domain-record --domain-id 47188 --record-type CNAME --record-name test --record-data example.com.

Help:
-h, --help: view the available flags

=end
require 'optparse'
require 'json'
require 'pp'
require 'rest_client'
require 'net/http'
require 'net/https'
require 'terminal-table'

options = {}
wrote_config_file = false

# Client specific things go here
begin
  fcontents = File.read(File.expand_path('~/.rubyocean')).strip.split(':')
  digitalocean_client_id = fcontents[0]
  digitalocean_api_key   = fcontents[1]
rescue
  digitalocean_client_id       = '' # THIS IS REQUIRED IF YOU DONT CREATE THE CONFIG FILE!
  digitalocean_api_key         = '' # THIS IS REQUIRED IF YOU DONT CREATE THE CONFIG FILE!
end

# The API entry point will _likely_ never change
digitalocean_api_entry_point = 'https://api.digitalocean.com'

# define all of the command line options
option_parser = OptionParser.new do |opts|

  opts.banner = 'Usage: rubyocean.rb [options]'

  options[:verbose] = false

  opts.separator ''
  opts.separator 'Specific options:'

  opts.on('-l', '--list-droplets', 'List droplets') do
    options[:list] = true
  end

  opts.on('-v', '--verbose', 'Run verbosely') do
    options[:verbose] = true
  end

  opts.on('-r', '--reboot DROPLET_ID', 'Reboot droplet') do |r|
    options[:reboot_droplet_id] = r
  end

  opts.on('-s', '--sizes', 'Droplet Sizes') do
    options[:sizes] = true
  end

  opts.on('-k', '--ssh-keys', 'List SSH Keys') do
    options[:ssh_keys] = true
  end

  opts.on('-g', '--regions', 'List available droplet regions') do
    options[:regions] = true
  end

  opts.on('-i', '--images', 'List available droplet images') do
    options[:images] = true
  end

  opts.on('--get-domains', 'Get Domain data') do
    options[:get_domain_data] = true
  end

  opts.on('--view-domain DOMAIN_ID', 'View data for specific Domain ID') do |vdomain|
    options[:view_domain] = vdomain
  end

  opts.on('--create-domain-record', 'Create a new domain record') do
    options[:create_domain_record] = true
  end

  opts.on('--record-type DOMAIN_RECORD_TYPE', 'The type of domain record to create: A, CNAME, NS, TXT, MX, SRV') do |drt|
    options[:domain_record_type] = drt
  end

  opts.on('--record-data DOMAIN_RECORD_DATA', 'Value of the record') do |drd|
    options[:domain_record_data] = drd
  end

  opts.on('--record-name DOMAIN_RECORD_NAME', 'Name, required for A, CNAME, TXT, SRV') do |drn|
    options[:domain_record_name] = drn
  end

  opts.on('--domain-id DOMAIN_ID', 'Modify for specific Domain ID') do |vdomain|
    options[:domain_id] = vdomain
  end

  opts.on('-c', '--create-droplet', 'Create a new droplet') do
    options[:create_droplet] = true
  end

  opts.on('--droplet-name DROPLET_NAME', 'Name (hostname) of the droplet') do |dn|
    options[:droplet_name] = dn
  end

  opts.on('--droplet-size DROPLET_SIZE', 'Size ID of the droplet (view available with -s)') do |ds|
    options[:droplet_size] = ds
  end

  opts.on('--droplet-image DROPLET_IMAGE', 'Image ID to use for the droplet') do |di|
    options[:droplet_image] = di
  end

  opts.on('--droplet-region DROPLET_REGION', 'Region ID of where to create the droplet (view available with -g)') do |dg|
    options[:droplet_region] = dg
  end

  opts.on('--droplet-keys DROPLET_KEYS', 'SSH keys to add to the droplet root account (if using multiple delimitate with a comma and no space)') do |dk|
    options[:droplet_keys] = dk
  end

  opts.on('--create-config', 'Create a config file containing your API Key and Client ID (will write to ~/.rubyocean)') do
    options[:create_config] = true
  end

  opts.on('--client-id CLIENT_ID', 'Specify your Client ID which will be written to the config file') do |cid|
    options[:client_id] = cid
  end

  opts.on('--api-key API_KEY', 'Specify your API Key which will be written to the config file') do |akey|
    options[:api_key] = akey
  end

  opts.on('-h', '--help', 'Show this message') do
    puts opts
    exit
  end
end

if options[:verbose]
  p options
end

# This will handle the actual GET request to the digitalocean API
def perform_get(api_url, param_arr)
  RestClient.get( api_url, { :params => param_arr }){ |response, request, result, &block|
    return response
  }
end

begin
  option_parser.parse!

  # lists your current droplets and some details about them
  if options.has_key?(:list)
    response = perform_get( digitalocean_api_entry_point + '/droplets/', { :client_id => digitalocean_client_id, :api_key => digitalocean_api_key } )
    if response.code == 200
      parsed = JSON.parse(response)

      rows = []
      parsed['droplets'].each do |droplet|
        rows <<  [droplet['id'].to_s, droplet['name'], droplet['status'], droplet['ip_address'], droplet['region_id'].to_s, droplet['size_id'].to_s, droplet['image_id'].to_s]
      end

      table = Terminal::Table.new :headings => ['id', 'name', 'status', 'public ip', 'region id', 'size id', 'image id'], :rows => rows
      puts table
    end
  end

  # reboots a droplet based on the droplet_id
  if options.has_key?(:reboot_droplet_id)
    response = perform_get( digitalocean_api_entry_point + '/droplets/' + options[:reboot_droplet_id].to_s + '/reboot/', { :client_id => digitalocean_client_id, :api_key => digitalocean_api_key } )
    if response.code == 200
      rows = []
      parsed = JSON.parse(response)
      rows << [parsed['status'], parsed['event_id'].to_s]

      table = Terminal::Table.new :title => 'Reboot Results', :headings => ['status', 'event id'], :rows => rows
      puts table
    else
      puts 'reboot failed with response: ' + response
    end
  end

  # lists available droplet sizes
  if options.has_key?(:sizes)
    response = perform_get( digitalocean_api_entry_point + '/sizes/', { :client_id => digitalocean_client_id, :api_key => digitalocean_api_key } )
    if response.code == 200
      parsed = JSON.parse(response)

      rows = []
      parsed['sizes'].each do |size|
        rows <<  [size['id'].to_s,  size['name']]
      end

      table = Terminal::Table.new :headings => ['id', 'size name (RAM)'], :rows => rows
      puts table
    end
  end

  # lists ssh keys tied to your account
  if options.has_key?(:ssh_keys)
    response = perform_get( digitalocean_api_entry_point + '/ssh_keys/', { :client_id => digitalocean_client_id, :api_key => digitalocean_api_key } )
    if response.code == 200
      parsed = JSON.parse(response)

      rows = []
      parsed['ssh_keys'].each do |key|
        rows <<  [key['id'].to_s, key['name']]
      end

      table = Terminal::Table.new :headings => ['id', 'ssh key name'], :rows => rows
      puts table
    end
  end

  # lists available droplet regions
  if options.has_key?(:regions)
    response = perform_get( digitalocean_api_entry_point + '/regions/', { :client_id => digitalocean_client_id, :api_key => digitalocean_api_key } )
    if response.code == 200
      parsed = JSON.parse(response)

      rows = []
      parsed['regions'].each do |region|
        rows << [region['id'].to_s, region['name']]
      end

      table = Terminal::Table.new :headings => ['id', 'region name'], :rows => rows
      puts table
    end
  end

  # lists available droplet images
  if options.has_key?(:images)
    response = perform_get( digitalocean_api_entry_point + '/images/', { :client_id => digitalocean_client_id, :api_key => digitalocean_api_key } )
    if response.code == 200
      parsed = JSON.parse(response)

      rows = []
      parsed['images'].each do |image|
        rows << [image['id'].to_s, image['name'] + ' (' + image['distribution'] + ')']
      end

      table = Terminal::Table.new :title => 'Available Droplet Images', :headings => ['id', 'name (distribution)'], :rows => rows
      puts table
    end
  end

  # lists the basics of all domains on your account
  if options.has_key?(:get_domain_data)
    response = perform_get( digitalocean_api_entry_point + '/domains', { :client_id => digitalocean_client_id, :api_key => digitalocean_api_key } )
    if response.code == 200
      parsed = JSON.parse(response)

      rows = []
      parsed['domains'].each do |domain|
        rows << [domain['id'].to_s, domain['name'], domain['ttl'].to_s]
      end

      table = Terminal::Table.new :title => 'Account Domains', :headings => %w('id', 'name', 'ttl'), :rows => rows
      puts table
    else
      puts 'getting domain data failed with response: ' + response
    end
  end

  # displays technical details about a specific domain
  if options.has_key?(:view_domain)
    response = perform_get( digitalocean_api_entry_point + '/domains/' + options[:view_domain].to_s, { :client_id => digitalocean_client_id, :api_key => digitalocean_api_key } )
    if response.code == 200
      rows = []
      parsed = JSON.parse(response)
      rows << ['DigitalOcean Domain ID', parsed['domain']['id'].to_s]
      rows << ['domain_name', parsed['domain']['name']]
      rows << ['TTL',  parsed['domain']['ttl'].to_s]
      rows << ['Zone File Errors ', parsed['domain']['zone_file_with_error'].to_s]

      table = Terminal::Table.new :title => 'Domain Details', :rows => rows
      puts table

      # we need to show the zone file here due to formatting
      puts "\nLive zone file: \n\n" + parsed['domain']['live_zone_file'] + "\n\n"
      puts "\nDomain errors: \n\n" + parsed['domain']['error'].to_s + "\n\n"
    else
      puts 'getting specific domain data failed with response: ' + response
    end
  end

  # creates a new DNS entry based on params specified by the user
  # this requires a few things to be passed in, as indicated by the 'mandatory' array
  if options.has_key?(:create_domain_record)
    mandatory = [:domain_record_type, :domain_record_data, :domain_record_name, :domain_id]
    missing   = mandatory.select{ |param| options[param].nil? }

    if not missing.empty?
      p "Missing options: #{missing.join(', ')}"
      exit
    end

    # Everything looks good, lets create the entry
    response = perform_get( digitalocean_api_entry_point + '/domains/' + options[:domain_id].to_s + '/records/new', { :client_id => digitalocean_client_id,
                                                                                                                      :api_key => digitalocean_api_key,
                                                                                                                      :record_type => options[:domain_record_type],
                                                                                                                      :data => options[:domain_record_data],
                                                                                                                      :name => options[:domain_record_name] } )
    if response.code == 200
      rows = []
      parsed = JSON.parse(response)
      rows << ['status', parsed['status']]
      rows << ['domain_id',parsed['record']['domain_id'].to_s]
      rows << ['record_type', parsed['record']['record_type']]
      rows << ['name', parsed['record']['name']]
      rows << ['data', parsed['record']['data']]

      table = Terminal::Table.new :title => 'DNS Results', :rows => rows
      puts table
    else
      puts 'error creating new entry, failed with response ' + response
    end
  end

  # creates a new droplet based on params specified by the user
  # this requires a few things to be passed in, as indicated by the 'mandatory' array
  if options.has_key?(:create_droplet)
    mandatory = [:droplet_name, :droplet_size, :droplet_image, :droplet_region, :droplet_keys]
    missing   = mandatory.select{ |param| options[param].nil? }

    if not missing.empty?
      p "Missing options: #{missing.join(', ')}"
      exit
    end

    # Everything looks good, lets create the entry
    response = perform_get( digitalocean_api_entry_point + '/droplets/new', { :client_id => digitalocean_client_id,
                                                                              :api_key => digitalocean_api_key,
                                                                              :name => options[:droplet_name],
                                                                              :size_id => options[:droplet_size],
                                                                              :image_id => options[:droplet_image],
                                                                              :region_id => options[:droplet_region],
                                                                              :ssh_key_ids => options[:droplet_keys]} )
    if response.code == 200
      rows = []
      parsed = JSON.parse(response)
      rows << ['status', parsed['status']]
      rows << ['droplet_id', parsed['droplet']['id'].to_s]
      rows << ['name', parsed['droplet']['name']]
      rows << ['image_id', parsed['droplet']['image_id'].to_s]
      rows << ['size_id', parsed['droplet']['size_id'].to_s]

      table = Terminal::Table.new :title => 'Droplet Creation Results', :rows => rows
      puts table
    else
      puts 'error creating new droplet, failed with response ' + response
    end
  end

  # writes the config file in the user homedir containing their client id and api key
  if options.has_key?(:create_config)
    mandatory = [:client_id, :api_key]
    missing   = mandatory.select{ |param| options[param].nil? }

    unless missing.empty?
      p "Missing options: #{missing.join(', ')}"
      exit
    end

    # Alright, we made it this far, write the file
    begin
      file = File.open(File.expand_path('~/.rubyocean'), 'w')
      file.write(options[:client_id] + ':' + options[:api_key])
      wrote_config_file = true
    rescue
      puts 'Error writing config file! Please ensure the file doesn\'t already exist and you have permission to write to the directory!'
        wrote_config_file = false
    ensure
      file.close unless file == nil
    end
  end

rescue
  p $!.to_s
  exit
end

if digitalocean_api_key.length < 10 && digitalocean_client_id.length < 10 && !wrote_config_file
  puts "Did you forget to set your API Key and Client ID values? You must either edit this file and define them, or run: \n\n"
  puts "./rubyocean.rb --create-config --client-id YOUR_CLIENT_ID --api-key YOUR_API_KEY\n\n"
end