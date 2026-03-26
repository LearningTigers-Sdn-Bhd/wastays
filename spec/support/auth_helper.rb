module AuthHelper
  def sign_in_as(user)
    post login_path, params: { email: user.email, password: user.password }
  end
end

RSpec.configure do |config|
  config.include AuthHelper, type: :request
end
