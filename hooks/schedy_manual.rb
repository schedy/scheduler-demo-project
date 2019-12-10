#!/bin/env ruby

require 'bundler/setup'

require 'ostruct'
require 'rest_client'
require "awesome_print"
require 'json'
require 'fcntl'
output_stream = IO.for_fd(STDOUT.fcntl(Fcntl::F_DUPFD))
STDOUT.reopen(STDERR)
p "*"*80

#STDOUT.reopen("/dev/null","w")
#STDOUT.reopen("schedy-manual-#{$$}-out","w")
#STDERR.reopen("schedy-manual-#{$$}-err","w")

def manual_wi_parser(wi)
	wi = JSON.parse(wi)
	description = OpenStruct.new
	if wi
		payload = wi
		description.default_project = payload["default_project"].to_s
		description.event_type = payload["event_type"].to_s
		description.author = "schedy-manual"
		description.package_project = {payload["package"].to_s => payload["project"].to_s}
		description.package_arch = {payload["package"].to_s => payload["arch"].to_s}
		description.package_repository = {payload["package"].to_s => payload["repo"].to_s}
		description.triggered_by_package = payload["package"].to_s
		description.project = payload["project"].to_s
		description.multiplier = payload["multiplier"].to_i
		description.target_tag = payload["target_tag"].split(',')
		description.target_name = [payload["target_name"]]
		description.target_resources = payload["target_resources"]
	end
	return description
end

begin
	#Parse workitem, create tasks and add tags.
	i = STDIN.read
	workitem_description = manual_wi_parser(i)
	Dir.chdir("project/creator")

	require_relative '../creator/schedy-execution-creator.rb'
	require_relative '../helpers.rb'

	execution = workitem_description_to_execution_description(workitem_description)
	execution["data"] = i
	output_stream.puts JSON.dump(execution)
end

p "*"*80

