class Guest::SessionsController < Guest::BaseController
  layout "application"
  skip_before_action :authenticate_guest!, raise: false

  def new
    redirect_to guest_dashboard_path if guest_logged_in?
  end

  def create
    phone = params[:phone]&.strip
    otp   = params[:otp]&.strip

    guest = ::Guest.find_by(phone: phone)

    if guest.nil?
      flash.now[:alert] = "No account found for that phone number."
      render :new, status: :unprocessable_entity
      return
    end

    unless guest.verify_otp(otp)
      flash.now[:alert] = "Invalid or expired code. Request a new one via WhatsApp."
      render :new, status: :unprocessable_entity
      return
    end

    guest.consume_otp!
    session[:guest_id] = guest.id
    redirect_to guest_dashboard_path, notice: "Welcome back, #{guest.name}!"
  end

  def verify
    token = params[:token]
    guest = ::Guest.find_by(magic_token_digest: Digest::SHA256.hexdigest(token.to_s))

    if guest&.verify_magic_token(token)
      guest.consume_magic_token!
      session[:guest_id] = guest.id
      redirect_to guest_dashboard_path, notice: "Welcome back, #{guest.name}!"
    else
      redirect_to guest_login_path, alert: "This link has expired or is invalid. Request a new one via WhatsApp."
    end
  end

  def destroy
    session[:guest_id] = nil
    redirect_to guest_login_path, notice: "You have been logged out."
  end
end
