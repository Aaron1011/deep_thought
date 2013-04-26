require "sinatra"
require "deep_thought/git"
require "deep_thought/deployer"

module DeepThought
  class Deploy < Sinatra::Base
    get '*' do
      [401, "I don't got what you're trying to GET."]
    end

    post '/' do
      [500, "Must supply app name."]
    end

    post '/:app' do
      app = params[:app]
      branch = params[:branch] || 'master'
      actions = params[:actions].split(',') if params[:actions]
      environment = params[:environment] if params[:environment]
      box = params[:box] if params[:box]

      project = Project.find_by_name(app)

      if !project
        return [500, "Hmm, that project doesn't appear to exist. Have you set it up?"]
      end

      hashes = Git.get_latest_commit_for_branch(project, branch)

      if !hashes
        return [500, "Woah - I can't seem to access that repo. Are you sure the URL is correct and that I have access to it?"]
      end

      hash = hashes[0]

      if !hash
        return [500, "Hmm, that branch doesn't appear to exist. Have you pushed it?"]
      end

      parameters = Hash["branch", branch]

      response = "executing deploy"

      if actions
        parameters["actions"] = actions

        actions.each do |action|
          response += "/#{action}"
        end
      end

      response += " #{app}/#{branch}/#{hash}"

      if environment
        parameters["env"] = environment
        response += " to #{environment}"

        if box
          parameters["box"] = box
          response += "/#{box}"
        end
      end

      DeepThought::Deployer.execute(project, parameters)

      response
    end

    post '/setup/:app' do
      app = params[:app]
      repo_url = params[:repo_url]
      deploy_type = params[:deploy_type]

      if !repo_url || !deploy_type
        return [500, "Sorry, but I need a project name, repo url, and deploy type. No exceptions, despite how nicely you ask."]
      end

      project = Project.new(:name => app, :repo_url => repo_url, :deploy_type => deploy_type)

      if project.save
        [200, "Set up new project called #{app} which deploys with #{deploy_type} and pulls from #{repo_url}."]
      else
        [422, "Shit, something went wrong: #{project.errors.messages}."]
      end
    end
  end
end
