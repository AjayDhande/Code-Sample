module Api
  class JobsController < ApplicationController
    before_filter :require_login
    before_filter :require_production, only: [:delivered]

    def index
      manager  = Job::DatatablesManagement.new(current_user)
      response = manager.index_response(params)
      render json: response
    end

    def delivered
      manager  = Job::DatatablesManagement.new(current_user)
      response = manager.delivered_response(params)
      render json: response
    end

    def start_up
      manager  = Job::DatatablesManagement.new(current_user)
      response = manager.startup_response(params)
      render json: response
    end

    def running
      manager  = Job::DatatablesManagement.new(current_user)
      response = manager.running_response(params)
      render json: response
    end

    def plates
      manager  = Job::DatatablesManagement.new(current_user)
      response = manager.plates_response(params)
      render json: response
    end

    def search
      if current_user.client_manager?
        @jobs = current_user.client.jobs.visible
      elsif current_user.client?
        @jobs = Job.visible.where(team_id: current_user.teams.map(&:id))
      else
        @jobs = Job.all
      end
      json, count = Job::SearchQuery.by_all search_param, @jobs, json: true
      render json: "{\"jobs_count\": #{count}, \"jobs\": #{json}}"
    end

    private

    def search_param
      params.require(:search)
    end
  end
end
