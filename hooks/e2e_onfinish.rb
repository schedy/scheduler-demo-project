#!/bin/env ruby

require 'bundler/setup'

require '../../config/environment.rb'
require 'rest-client'
require '../config.rb'
require 'logger'
require 'rest-client'
PROCESSOR_SCHEDY_URL = "http://schedy-server:3000"
@log = Logger.new(STDOUT)

def pcap_post_processing(params)
	@task_id = params["task_id"]
	@status = params["status"]
	@filter_regexp = params["filter_regexp"]

	@log.info "PCAP postprocessing for task #{@task_id} has started."
	processor_endpoint = "#{PROCESSOR_SCHEDY_URL}/executions/create/postprocess"
        processed_artifact_destination = "#{EXTERNAL_SCHEDULER_URI}/tasks/#{@task_id}/artifacts"
	target_task = Task.find(@task_id)
	execution_id = target_task.execution_id
	execution_created_at = target_task.execution.created_at
	required_packages = target_task.description["required_packages"]
	recipes = target_task.description["recipes"]
	required_repos = target_task.description["required_repos"]
	selected_artifacts = target_task.artifacts.map {|artifact| artifact.name}.select{|name| name[@filter_regexp]}
        if selected_artifacts.size < 1
        	@log.info 'Filters did not return any matches ! no result will be reported.'
                return 0
        end
        @log.info "List of artifacts: #{selected_artifacts.join(' ')}"
        raw_artifact_sources = selected_artifacts.map { |artifact_name| "#{EXTERNAL_SCHEDULER_URI}/tasks/#{@task_id}/artifacts/#{artifact_name}" }
        @log.info "Artifact URIs: #{raw_artifact_sources.join(' ')}"


	payload={
		task_view_url: "#{EXTERNAL_SCHEDULER_URI}/?show=execution&execution_id=#{target_task.execution_id}&task_unfolded=#{@task_id}",
                task_id: @task_id,
		execution_id: execution_id,
		execution_created_at: execution_created_at,
                raw_artifact_sources: raw_artifact_sources,
                processed_artifact_destination: processed_artifact_destination,
		required_packages: required_packages,
		recipes: recipes,
		required_repos: required_repos
	}
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
