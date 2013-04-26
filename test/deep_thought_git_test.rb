require File.expand_path '../test_helper.rb', __FILE__

class DeepThoughtGitTest < MiniTest::Unit::TestCase
  def setup
    @project = DeepThought::Project.new(:name => '_test', :deploy_type => 'capy')
  end

  def test_git_setup_failed
    @project.repo_url = 'http://fake.url'
    assert !DeepThought::Git.setup(@project)
  end

  def test_git_setup_success
    @project.repo_url = './test/fixtures/test'
    assert DeepThought::Git.setup(@project)
  end

  def test_git_get_latest_commit_for_branch_success
    @project.repo_url = './test/fixtures/test'
    assert_kind_of Array, DeepThought::Git.get_latest_commit_for_branch(@project, 'master')
  end

  def test_git_get_latest_commit_for_branch_failed
    @project.repo_url = './test/fixtures/test'
    assert_empty DeepThought::Git.get_latest_commit_for_branch(@project, 'no-branch')
  end
end
