require "rails_helper"

RSpec.describe "HotelPortal::RefundRequests", type: :request do
  it "refund request routes are not routable for hotel portal" do
    expect { Rails.application.routes.recognize_path("/hotel/1/refund_requests", method: :get) }
      .to raise_error(ActionController::RoutingError)
    expect { Rails.application.routes.recognize_path("/hotel/1/refund_requests/1", method: :get) }
      .to raise_error(ActionController::RoutingError)
    expect { Rails.application.routes.recognize_path("/hotel/1/refund_requests/1/approve", method: :patch) }
      .to raise_error(ActionController::RoutingError)
    expect { Rails.application.routes.recognize_path("/hotel/1/refund_requests/1/reject", method: :patch) }
      .to raise_error(ActionController::RoutingError)
    expect { Rails.application.routes.recognize_path("/hotel/1/refund_requests/1/complete", method: :patch) }
      .to raise_error(ActionController::RoutingError)
  end
end
