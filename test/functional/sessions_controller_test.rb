require 'test_helper'
require 'sessions_controller'

# Re-raise errors caught by the controller.
class SessionsController; def rescue_action(e) raise e end; end

class SessionsControllerTest < ActionController::TestCase
  # Be sure to include AuthenticatedTestHelper in test/test_helper.rb instead
  # Then, you can remove it from this and the units test.
  include AuthenticatedTestHelper

  fixtures :users,:people

  def setup
    @controller = SessionsController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
  end

  test "sessions#index redirects to session#new" do
    get :index
    assert_redirected_to root_path
  end

  test "session#show redirects to root page" do
    get :show
    assert_redirected_to root_path
  end

  def test_index_not_logged_in
    get :new
    assert_response :success

    User.destroy_all #remove all users
    assert_equal 0,User.count
    get :new
    assert_response :redirect
    assert_redirected_to signup_url
  end

  def test_title
    get :new
    assert_select "title",:text=>/The Sysmo SEEK.*/, :count=>1
  end

  def test_should_login_and_redirect
    post :create, :login => 'quentin', :password => 'test'
    assert session[:user_id]
    assert_response :redirect
  end

  #FIXME: check whether doing a redirect is a problem - this is a test generated by the restful_auth.. plugin, so is clearly there for a reason
#  def test_should_fail_login_and_not_redirect
#    post :create, :login => 'quentin', :password => 'bad password'
#    assert_nil session[:user_id]
#    assert_response :success
#  end

  def test_should_logout
    login_as :quentin
    @request.cookies[:open_id] = 'http://fred.openid.org'
    @request.env['HTTP_REFERER'] = '/data_files'
    get :destroy
    assert_nil session[:user_id]
    assert_nil cookies[:open_id]
    assert_response :redirect
  end

  def test_should_remember_me
    post :create, :login => 'quentin', :password => 'test', :remember_me => "on"
    assert_not_nil @response.cookies["auth_token"]
  end

  def test_should_not_remember_me
    post :create, :login => 'quentin', :password => 'test', :remember_me => "off"
    assert_nil @response.cookies["auth_token"]
  end

  def test_should_delete_token_on_logout
    login_as :quentin
    @request.env['HTTP_REFERER'] = '/data_files'
    get :destroy
    assert_equal @response.cookies["auth_token"], nil
  end

  def test_should_login_with_cookie
    users(:quentin).remember_me
    @request.cookies["auth_token"] = cookie_for(:quentin)
    get :new
    assert @controller.send(:logged_in?)
  end

  def test_should_fail_expired_cookie_login
    users(:quentin).remember_me
    users(:quentin).update_attribute :remember_token_expires_at, 5.minutes.ago
    @request.cookies["auth_token"] = cookie_for(:quentin)
    get :new
    assert !@controller.send(:logged_in?)
  end

  def test_should_fail_cookie_login
    users(:quentin).remember_me
    @request.cookies["auth_token"] = 'invalid_auth_token'
    get :new
    assert !@controller.send(:logged_in?)
  end

  def test_non_validated_user_should_redirect_to_new_with_message
    post :create, :login => 'aaron', :password => 'test'
    assert !session[:user_id]
    assert_redirected_to login_path
    assert_not_nil flash[:error]    
    assert flash[:error].include?("You still need to activate your account.")
  end

  def test_partly_registed_user_should_redirect_to_select_person
    post :create, :login => 'part_registered', :password => 'test'
    assert session[:user_id]
    assert_equal users(:part_registered).id,session[:user_id]
    assert_not_nil flash.now[:notice]
    assert_redirected_to select_people_path
  end

  test 'should redirect to root after logging out from the search result page' do
      login_as :quentin
      @request.env['HTTP_REFERER']= "http://test.host/search/"
      get :destroy
      assert_redirected_to :root
  end

  test 'should redirect to back after logging out from the page excepting search result page' do
      login_as :quentin
      @request.env['HTTP_REFERER']= "http://test.host/data_files/"
      get :destroy
      assert_redirected_to :back
  end

  test 'should redirect to root after logging in from the search result page' do
      @request.env['HTTP_REFERER']= "http://test.host/search"
      post :create, :login => 'quentin', :password => 'test'
      assert_redirected_to :root
  end

  test 'should redirect to back after logging in from the page excepting search result page' do
      @request.env['HTTP_REFERER']= "http://test.host/data_files/"
      post :create, :login => 'quentin', :password => 'test'
      assert_redirected_to :back
  end

  protected

    def cookie_for(user)
      users(user).remember_token
    end
end
