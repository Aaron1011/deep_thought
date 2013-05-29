require File.expand_path '../test_helper.rb', __FILE__

class DeepThoughtAppTest < MiniTest::Unit::TestCase
  include Rack::Test::Methods
  include Capybara::DSL

  def setup
    DatabaseCleaner.start

    @user_email = 'test@test.com'
    @user_password = 'secret'
    @user = DeepThought::User.create(:email => @user_email, :password => @user_password, :password_confirmation => @user_password)
  end

  def teardown
    Capybara.reset_sessions!
    Capybara.use_default_driver

    DatabaseCleaner.clean
  end

  def app
    DeepThought.app
  end

  def test_app_root_logged_out
    get '/'
    follow_redirect!
    assert last_response.ok?
    assert_equal "http://example.org/login", last_request.url
  end

  def test_app_root_logged_in
    login(@user_email, @user_password)

    assert_equal page.status_code, 200
    assert_equal "http://www.example.com/", page.current_url
  end

  def test_app_logout
    login(@user_email, @user_password)

    assert_equal page.status_code, 200
    assert_equal "http://www.example.com/", page.current_url

    logout

    visit '/'
    assert_equal page.status_code, 200
    assert_equal "http://www.example.com/login", page.current_url
  end

  def test_app_user_generate_api_key
    login(@user_email, @user_password)

    visit "/users/#{@user.id}"
    assert_equal "http://www.example.com/users/#{@user.id}", page.current_url
    assert page.has_content?('no api key (yet)')

    DeepThought::User.any_instance.expects(:generate_api_key)

    @user.api_key = '12345'
    @user.save!

    within(".user-api-key") do
      click_button 'generate new api key'
    end

    assert_equal "http://www.example.com/users/#{@user.id}", page.current_url
    assert page.has_content?('12345')

    logout

    login(@user_email, @user_password)

    assert_equal page.status_code, 200
    assert_equal "http://www.example.com/", page.current_url
  end

  def test_app_add_user
    login(@user_email, @user_password)

    visit "/users/new"
    within(".content > form") do
      fill_in 'email', :with => 'new@user.email'
      fill_in 'password', :with => 'secret'
      fill_in 'password_confirmation', :with => 'secret'
      click_button 'create user'
    end

    assert_equal "http://www.example.com/users", page.current_url
    assert page.has_content?('new@user.email')
  end

  def test_app_delete_user
    login(@user_email, @user_password)

    visit "/users/new"
    within(".content > form") do
      fill_in 'email', :with => 'new@user.email'
      fill_in 'password', :with => 'secret'
      fill_in 'password_confirmation', :with => 'secret'
      click_button 'create user'
    end

    assert page.has_content?('new@user.email')

    within(".list") do
      click_link 'new@user.email'
    end

    click_button 'delete user'

    assert_equal "http://www.example.com/users", page.current_url
    assert !page.has_content?('new@user.email')
  end

  def test_app_user_update_email
    login(@user_email, @user_password)

    within("nav") do
      click_link "me"
    end

    within(".user-info > form") do
      fill_in 'email', :with => 'new@user.email'
      click_button 'update'
    end

    assert page.has_content?('new@user.email')

    logout

    login('new@user.email', @user_password)

    assert_equal "http://www.example.com/", page.current_url
  end

  def test_app_project_branches
    project = DeepThought::Project.create(:name => '_test', :repo_url => './test/fixtures/git-test', :deploy_type => 'mock')

    login(@user_email, @user_password)

    within(".list") do
      click_link '_test'
    end

    assert page.has_select?('deploy[branch]', :options => ['master', 'topic'])
  end

  def test_app_project_deploy_no_attributes
    DeepThought::Notifier.stubs(:notify)

    project = DeepThought::Project.create(:name => '_test', :repo_url => './test/fixtures/git-test', :deploy_type => 'mock')

    assert_equal DeepThought::Deploy.count, 0

    deployer = mock('class')
    deployer.expects(:new).returns(deployer)
    deployer.expects(:execute).returns(true)
    DeepThought::Deployer.register_adapter('mock', deployer)

    login(@user_email, @user_password)

    within(".list") do
      click_link '_test'
    end

    within(".deploy > form") do
      click_button 'deploy'
    end

    assert_equal DeepThought::Deploy.count, 1

    deploy = DeepThought::Deploy.all[0]

    assert_equal deploy.branch, 'master'
    assert_equal deploy.environment, nil
    assert_equal deploy.box, nil
    assert_equal deploy.actions, nil
    assert_equal deploy.variables, nil
    assert_equal deploy.via, 'web'
  end

  def test_app_project_deploy_with_attributes
    DeepThought::Notifier.stubs(:notify)

    project = DeepThought::Project.create(:name => '_test', :repo_url => './test/fixtures/git-test', :deploy_type => 'mock')

    assert_equal DeepThought::Deploy.count, 0

    deployer = mock('class')
    deployer.expects(:new).returns(deployer)
    deployer.expects(:execute).returns(true)
    DeepThought::Deployer.register_adapter('mock', deployer)

    login(@user_email, @user_password)

    within(".list") do
      click_link '_test'
    end

    within(".deploy > form") do
      select('topic', :from => 'deploy[branch]')
      fill_in 'environment', :with => 'development'
      fill_in 'box', :with => 'dev1'
      # TODO: Test actions and variables (need to integrate JavaScript into testing)
      click_button 'deploy'
    end

    assert_equal DeepThought::Deploy.count, 1

    deploy = DeepThought::Deploy.all[0]

    assert_equal deploy.branch, 'topic'
    assert_equal deploy.environment, 'development'
    assert_equal deploy.box, 'dev1'
    assert_equal deploy.actions, nil
    assert_equal deploy.variables, nil
    assert_equal deploy.via, 'web'
  end

  def test_app_project_history
    DeepThought::Notifier.stubs(:notify)

    project = DeepThought::Project.create(:name => '_test', :repo_url => './test/fixtures/git-test', :deploy_type => 'mock')

    login(@user_email, @user_password)

    visit '/projects/_test'

    click_link 'history...'

    assert !page.has_content?("deploy master by #{@user_email}")

    deploy = DeepThought::Deploy.new(:project_id => project.id, :user_id => @user.id, :branch => 'master', :commit => '12345')

    deployer = mock('class')
    deployer.expects(:new).returns(deployer)
    deployer.expects(:execute).with(deploy).returns(true)
    DeepThought::Deployer.register_adapter('mock', deployer)

    deploy.save

    visit '/projects/_test/deploys'

    assert page.has_content?("deploy master by #{@user_email}")
  end

  def test_app_add_project
    login(@user_email, @user_password)

    visit "/projects/add/new"
    within(".content > form") do
      fill_in 'name', :with => 'test'
      fill_in 'repo', :with => 'repo'
      fill_in 'type', :with => 'type'
      click_button 'create project'
    end

    assert_equal "http://www.example.com/", page.current_url
    assert page.has_content?('test')

    visit "/projects/edit/test"

    assert_equal find_field('name').value, 'test'
    assert_equal find_field('repo').value, 'repo'
    assert_equal find_field('type').value, 'type'
    assert page.has_select?('project[ci]', :selected => 'true')
  end

  def test_app_edit_project
    login(@user_email, @user_password)

    visit "/projects/add/new"
    within(".content > form") do
      fill_in 'name', :with => 'test'
      fill_in 'repo', :with => 'repo'
      fill_in 'type', :with => 'type'
      click_button 'create project'
    end

    assert page.has_content?('test')

    visit "/projects/edit/test"
    within(".content > form") do
      fill_in 'name', :with => 'test2'
      fill_in 'repo', :with => 'repo2'
      fill_in 'type', :with => 'type2'
      select('false', :from => 'project[ci]')
      click_button 'update project'
    end

    assert_equal "http://www.example.com/projects/test2", page.current_url
    assert page.has_content?('Now pondering: test2')

    visit "/projects/edit/test2"

    assert_equal find_field('name').value, 'test2'
    assert_equal find_field('repo').value, 'repo2'
    assert_equal find_field('type').value, 'type2'
    assert page.has_select?('project[ci]', :selected => 'false')
  end

  def test_app_delete_project
    login(@user_email, @user_password)

    visit "/projects/add/new"
    within(".content > form") do
      fill_in 'name', :with => 'test'
      fill_in 'repo', :with => 'repo'
      fill_in 'type', :with => 'type'
      click_button 'create project'
    end

    assert page.has_content?('test')

    within(".list") do
      click_link 'test'
    end

    click_link 'edit...'

    click_button 'delete project'

    assert_equal "http://www.example.com/", page.current_url
    assert !page.has_content?('test')
  end
end
