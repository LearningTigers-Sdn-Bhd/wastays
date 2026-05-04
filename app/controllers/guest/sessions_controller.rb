class Guest::SessionsController < Guest::BaseController
  layout "application"
  skip_before_action :authenticate_guest!, raise: false
  before_action :redirect_if_guest_logged_in!, only: %i[new request_magic_link]

  def new; end

  def create
    phone = params[:phone]&.strip
    otp   = params[:otp]&.strip

    guest = find_guest_by_phone(phone)

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

  def request_magic_link
    email = params[:email]&.strip&.downcase

    if email.blank?
      flash.now[:alert] = "Please enter your email address."
      render :new, status: :unprocessable_entity
      return
    end

    guest = ::Guest.find_by(email: email)

    unless guest
      flash.now[:alert] = "No account found for that email. Please create an account to continue."
      render :new, status: :unprocessable_entity
      return
    end

    if guest.magic_link_on_cooldown?
      flash[:alert] = "A link was already sent. Please wait 2 minutes before requesting again."
      redirect_to guest_login_path
      return
    end

    token = guest.generate_magic_token!
    GuestMailer.magic_link(guest, token).deliver_later

    redirect_to guest_login_path(email_sent: true)
  end

  def verify
    token = params[:token]
    guest = ::Guest.find_by(magic_token_digest: Digest::SHA256.hexdigest(token.to_s))

    if guest&.verify_magic_token(token)
      guest.consume_magic_token!
      session[:guest_id] = guest.id
      redirect_to guest_dashboard_path, notice: "Welcome back, #{guest.name}!"
    else
      redirect_to guest_login_path, alert: "This link has expired or is invalid. Request a new one."
    end
  end

  def destroy
    session[:guest_id] = nil
    redirect_to guest_login_path, notice: "You have been logged out."
  end

  private

  def redirect_if_guest_logged_in!
    redirect_to guest_dashboard_path if guest_logged_in?
  end

  def find_guest_by_phone(raw)
    PhoneIdentity.find_guest(raw)
  end
end
