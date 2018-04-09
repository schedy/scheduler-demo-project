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

	opts.on("-q n","--queue-name=n","example: testing") { |e|
		options["queue_name"] = e
	}
	opts.on("-f n","--json-file=n","json file to use as workitem") { |e|
		options["json_file"] = e
	}
	begin
		opts.parse!
		options["queue_name"] ||= "testing"
		mandatory = [options["json_file"]]
		missing = mandatory.select { |e| e.nil? == true }
		unless missing.empty?
			raise OptionParser::MissingArgument
		end
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
	file = File.open(options["json_file"], "rb")
	json = file.read
	file.close
	x.publish(json, :routing_key => q.name)
	conn.close
end

dispatcher(options)
