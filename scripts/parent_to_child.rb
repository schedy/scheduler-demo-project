#!/bin/ruby

require 'active_record'

ActiveRecord::Base.establish_connection(
  :adapter => "postgresql",

  :database => "scheduler_worker")

class Resource < ActiveRecord::Base
end

def parent_to_child
	resources = Resource.all
	resources.map { |resource|
		resource_id = resource.id
		parent_id = resource.parent_id
		p "Resource id: #{resource_id}"
		if parent_id && resource.description["options"] == "SPI_ADAPTER"
			p "Found parent_id: #{parent_id}"
			child_id = Resource.where(parent_id: parent_id).pluck(:id).find { |id| id != resource_id}
			p "Child id: #{Resource.where(parent_id: parent_id).pluck(:id).find { |id| id != resource_id} }"
			Resource.where(id: child_id).update_all("children_ids = children_ids || #{resource_id}")
		else
			p 'No parent id !'
		end
	}
end

parent_to_child()
