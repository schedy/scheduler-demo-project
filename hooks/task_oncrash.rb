#!/bin/env ruby

require 'bundler/setup'

require '../../config/environment.rb'
require 'rest-client'
require '../config.rb'
require 'logger'
require 'rest-client'
PROCESSOR_SCHEDY_URL = "http://schedy-server:3000"
@log = Logger.new(STDOUT)

def lock_resource(params)
	@task_id = params["task_id"]
	@status = params["status"]

	@log.info "PCAP postprocessing for task #{@task_id} has started."
	@log.info "Prepared payload : #{payload.to_s}"
        processor_request_response = RestClient.post(processor_endpoint,payload)
	@log.info "Requested an execution for artifacts. Result: #{processor_request_response.code}."
end




task_id = ARGV[0]
status = ARGV[1]
FILTER_REGEXP = Regexp.new /pcap/
params = Hash.new("")

@log.info "Received event from Task ID: #{task_id}, Status: #{status}"

params["task_id"] = task_id
params["status"] = status
params["filter_regexp"] = FILTER_REGEXP
params["proxy"] = "https://http-proxy"
@log.info "Sending request: #{params.to_s}"
pcap_post_processing(params)
