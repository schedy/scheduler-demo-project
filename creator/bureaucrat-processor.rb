require 'json'
require 'bunny'
require 'slop'

#require_relative '../terminal.rb'



# parsing commandline arguments
OPTIONS = Slop.parse { |o|
	o.string '-q', '--queue-name', 'RabbitMQ queue name (default: testing)', default: 'testing'
	o.string '-H', '--rabbit-host', 'RabbitMQ host address (default: 127.0.0.1)', default: '127.0.0.1'
	o.string '-U', '--rabbit-user', 'RabbitMQ user name (default: '')', default: 'guest'
	o.string '-P', '--rabbit-password', 'RabbitMQ user password (default: '')', default: 'guest'
	o.string '-r', '--require-file', 'File that defines workitem_process(workitem) function'
	o.on '-h', '--help' do puts o; exit 0; end
}


# exception which prevents re-processing of the workitem (message will be ack-ed in rabbit). other exceptions may lead to processing retry.
class PermanentWorkItemError < Exception; end


# loading the main workitem processing function
def crash_on_missing_workitem_process_function
	$stderr.puts "You need to (re-)define the workitem_process(workitem) function in some file, and require that file using the -r option."
	exit 1
end
crash_on_missing_workitem_process_function if not OPTIONS["require-file"]
require_relative OPTIONS["require-file"]
crash_on_missing_workitem_process_function if not defined? workitem_process


#Create a new bunny connection and initialize it.
puts "Connecting to the rabbitmq"
connection = Bunny.new(host: OPTIONS['rabbit-host'], vhost: "/", user: OPTIONS['rabbit-user'], password: OPTIONS['rabbit-password'])
connection.start


#Create a new channel and queue
channel = connection.create_channel
queue  = channel.queue(OPTIONS['queue-name'], durable: true)
channel.prefetch(1)


#Create an exchange for the bindings
exchange = Bunny::Exchange.new(channel, :direct, OPTIONS['queue-name'], durable: true)


#Create the bindings
queue.bind(OPTIONS['queue-name'])
queue.bind(OPTIONS['queue-name'], routing_key: OPTIONS['queue-name'])


#Validate if queue exists.
raise "Why? Queue does not exist!" if not connection.queue_exists?(OPTIONS['queue-name'])


#Subscribe and wait for messages from the queue
puts "Waiting for workitems"
queue.subscribe(block: true, manual_ack: true) do |delivery_info, metadata, payload|
	begin
		puts "Received a workitem wi-#{delivery_info.delivery_tag}"
		workitem = JSON.parse(payload)["args"][0]
		puts workitem

		should_we_ack = workitem_process(workitem)

		puts "Workitem processing finished, ack: " + should_we_ack.inspect
		channel.ack(delivery_info.delivery_tag, false) if should_we_ack
	rescue PermanentWorkItemError => error
		channel.ack(delivery_info.delivery_tag, false)
		$stderr.puts error.to_s
		error.backtrace.each { |line| $stderr.puts line.inspect }
		exit 2
	rescue Exception => error
		$stderr.puts error.to_s
		error.backtrace.each { |line| $stderr.puts line.inspect }
		exit 3
	end
end
