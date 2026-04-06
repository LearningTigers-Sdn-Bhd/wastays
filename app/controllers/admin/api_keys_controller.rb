class Admin::ApiKeysController < Admin::BaseController
  def index
    @api_keys = ApiKey.all.order(created_at: :desc)
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
      redirect_to admin_api_keys_path, notice: "API Key created: #{@api_key.token}"
    else
      render :new, status: :unprocessable_entity
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
