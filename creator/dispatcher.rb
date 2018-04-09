#!/bin/env ruby
require 'rest_client'
require "awesome_print"
require 'json'
require 'bunny'
require '../config.rb'
require 'optparse'

options={}

OptionParser.new { |opts|

	opts.banner = "Usage: bundle exec ruby dispatch-example.rb [options]"

	opts.on("-j n","--project=n","example: obs-project") { |e|
		options["project"] = e
	}
	opts.on("-p n","--package=n","example: obs-package") { |e|
		options["package"] = e
	}
	opts.on("-q n","--queue-name=n","example: testing") { |e|
		options["queue_name"] = e
	}
	opts.on("-u n","--username=n","example: john_doe") { |e|
		options["username"] = e
	}
	opts.on("-m n","--multiplier=n","example: 1") { |e|
		options["multiplier"] = e
	}
	opts.on("-e n","--eventtype=n","example: MANUAL or NIGHTLY") { |e|
		options["eventtype"] = e
	}
	opts.on("-a n","--arch=n","example: i586") { |e|
		options["arch"] = e
	}
	opts.on("-r n","--repository=n","example: fedora_23") { |e|
		options["repository"] = e
	}
	opts.on("-c n","--parentproject=n","example: fedora") { |e|
		options["parentproject"] = e
	}
		
	begin
		opts.parse!
		options["queue_name"] ||= "testing"
		options["username"] ||= "john_doe"
		options["multiplier"] ||= "1"
		options["eventtype"] ||= "MANUAL"
		options["arch"] ||= "i586"
		options["repository"] ||= "fedora_23"
		mandatory = [options["project"],options["package"]]
		missing = mandatory.select { |e| e.nil? == true }
		unless missing.empty?
			raise OptionParser::MissingArgument
		end
		options["parentproject"] ||= options["project"]
	rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
		puts opts.help
		raise
	end
}

def dispatcher(options)
	#Get a bunny connection, create channel and queue, and publish a message to default exchange. bureaucrat_msgs routing key will help CIBot for identifying message.
	STDOUT.sync = true
	puts options
	conn = Bunny.new(:host => (RABBIT_HOST or 'localhost'), :vhost => "/", :user => RABBIT_USER, :password => RABBIT_PASS)
	conn.start
	puts "Getting a new channel."
	ch = conn.create_channel
	q = ch.queue(options["queue_name"],:durable => true)
	x = ch.default_exchange
	puts "Publishing workitem."
	x.publish(
		{"args" => [
			{"multiplier" => options["multiplier"],
				"payload" => {
					"project" => options["project"],
					"package" => options["package"],
					"eventtype" => options["eventtype"],
					"results" => [{"package" => options["package"], "project" => options["project"], "arch" => options["arch"], "repository" => options["repository"]}],
					"parent_project" => options["parentproject"],
					"payload" => {},
					"pr" => {"username" => options["username"]}
				}}
		]}.to_json, :routing_key => q.name)
	conn.close
end

dispatcher(options)
