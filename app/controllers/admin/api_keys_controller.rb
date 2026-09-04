class Admin::ApiKeysController < Admin::BaseController
  def index
    @all_api_keys = ApiKey.all.order(created_at: :desc)
    @api_keys = @all_api_keys.page(params[:page]).per(25)
    @generated_api_key_token = session.delete(:generated_api_key_token)
    @generated_api_key_name = session.delete(:generated_api_key_name)
  end

  def docs
    @category = params[:category] || "authentication"
    # Renders the API documentation page with specific category context
  end

  def new
    @api_key = ApiKey.new
  end

  def create
    @api_key = ApiKey.new(api_key_params)
    if @api_key.save
      session[:generated_api_key_token] = @api_key.token
      session[:generated_api_key_name] = @api_key.name
      redirect_to admin_api_keys_path
    else
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    @api_key = ApiKey.find(params[:id])
    @api_key.update(status: "revoked")
    redirect_to admin_api_keys_path, notice: "API Key revoked."
  end

  private

  def api_key_params
    params.require(:api_key).permit(:name, :bearer_type, :bearer_id)
  end
end
