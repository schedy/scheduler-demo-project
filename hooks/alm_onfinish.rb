#!/bin/ruby
require '../../config/environment.rb'
require_relative '../config.rb'
require 'rest-client'
require 'base64'
require 'nokogiri'
require 'awesome_print'
require 'uri'

def authenticate(base_url,auth)
        enc = Base64.encode64(auth)
        @authHeader = "Basic #{enc}"
        #Get basic auth.
        phase1_auth= RestClient.get("#{base_url}/authentication-point/authenticate",{"Authorization": @authHeader}) { |res,req,result| @jar = res.cookie_jar }
        #Get a session.
        phase2_auth = RestClient.post("#{base_url}/rest/site-session",{"Authorization": @authHeader},{:cookies => @jar })  { |res,req,result|  @jar = res.cookie_jar }
        #Check if logged in.
        loggedinresponse = RestClient.get("#{base_url}/rest/is-authenticated",:cookies => @jar) { |res,req,result| p res }
        if loggedinresponse.code == 200
                p 'Connection established !'
        else
                p 'Connection failed !'
        end

end

def getDomainAndProject(base_url)

        #Get domains' and projects' names
        domains_doc = Nokogiri::XML(
                RestClient.get("#{base_url}/api/domains",{:Authorization=> @authHeader,:cookies => @jar}) { |res,req,result| p res }
        )
        domains_doc.css('Domain').each do |domain|
                @domain = domain["Name"]
                projects_doc = Nokogiri::XML(RestClient.get("#{base_url}/api/domains/#{@domain}/projects",:cookies => @jar){ |res,req,result| p res.body })
                projects_doc.css('Project').each do |project|
                        @project = project["Name"]
                end
        end
        if @domain.nil? || @project.nil? then raise 'Could not get domain or project !' end
end

#INFO: XUnit parsing for tests. If we need rather sophisticated XML to upload, this part needs to change.


def updateRun(base_url,run_id,task_id,execution_id)
    state = if Task.find(task_id).task_values.find_by(property_id: 4).value.value == "PASS" then 'Passed' else 'Failed' end
    execution_url =URI.encode "#{EXTERNAL_SCHEDULER_URI}?show=execution&execution_id=#{execution_id}&task_unfolded=#{task_id}",/&/
    xmldata="<Entity Type=\"run\"><Fields><Field Name=\"status\"><Value>#{state}</Value></Field><Field Name=\"user-13\"><Value>#{execution_url}</Value></Field></Fields></Entity>"
    @alm_project_endpoint= "/api/domains/#{@domain}/projects/#{@project}"
    @alm_run_endpoint = "/runs/#{run_id}"
    p RestClient.get("#{base_url}/rest/domains/FOO/projects/BAR/customization/entities/test/fields?alt=application/json",{:Authorization=> @authHeader,:cookies => @jar}) { |res,req,result| p req.to_s,res.body } 
    puts ["Dispatching a request for:",'run_id:',run_id,'to',base_url+@alm_project_endpoint+@alm_run_endpoint+run_id.to_s,'with payload:',xmldata].join(' ')
    update_run_request = RestClient.put("#{base_url}/rest/domains/#{@domain}/projects/#{@project}/runs/#{run_id}",xmldata,{:content_type => :xml,:cookies =>  @jar}) { |res,req,result|
	    if res.code == 200 then puts ["ALM Hook Request Successful !",run_id,xmldata].join("\n") else puts 'ALM Hook Request Failed: '+res.to_s end
    }
end


#Main starts here.

@jar = nil

@url = ALM_URL #ARGV[0]
@creds = ALM_CRED #ARGV[0]
@execution_id = ARGV[0]
@task_status = ARGV[1]
authenticate(@url,@creds)
getDomainAndProject(@url)
@alm_project_endpoint= "/api/domains/#{@domain}/projects/#{@project}"
@alm_run_endpoint = "/runs/#{@run_id}"


target_execution = Execution.find(@execution_id)
run_id = JSON.parse(target_execution.data)["run_id"]
target_resource = JSON.parse(target_execution.data)["target_resource"]

target_tasks = target_execution.tasks.map { |task| {task_id: task.id, run_id: run_id, target_resource: target_resource} }
target_tasks.each { |task_obj| updateRun(@url,task_obj[:run_id],task_obj[:task_id],@execution_id) }

