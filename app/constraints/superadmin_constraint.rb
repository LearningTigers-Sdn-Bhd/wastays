class SuperadminConstraint
  def matches?(request)
    return true if Rails.env.development?

    user_id = request.session[:user_id]
    return false unless user_id

    user = User.find_by(id: user_id)
    user&.superadmin?
  end
end
