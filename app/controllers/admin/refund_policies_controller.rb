class Admin::RefundPoliciesController < Admin::BaseController
  def show
    @refund_policy = RefundPolicy.first_or_initialize
    render "admin/refund_policy/show"
  end

  def update
    @refund_policy = RefundPolicy.first_or_initialize
    if @refund_policy.update(refund_policy_params)
      redirect_to admin_refund_policy_path, notice: "Refund policy updated."
    else
      render "admin/refund_policy/show", status: :unprocessable_entity
    end
  end

  def destroy
    RefundPolicy.delete_all
    redirect_to admin_refund_policy_path, notice: "Refund policy cleared."
  end

  private

  def refund_policy_params
    params.require(:refund_policy).permit(:min_days_before_checkin, :refund_percentage)
  end
end
