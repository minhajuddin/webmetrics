defmodule WebmetricsWeb.PageController do
  use WebmetricsWeb, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
