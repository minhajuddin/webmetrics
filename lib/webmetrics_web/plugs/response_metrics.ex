defmodule ResponseMetrics do
  @behaviour Plug

  defmodule ETSOwner do
    use GenServer

    def start_link(_) do
      GenServer.start_link(__MODULE__, [:ok], name: __MODULE__)
    end

    def init(state) do
      ResponseMetrics.metrics
      |> Enum.each(fn metric ->
        :ets.new(metric, [:named_table, :set, {:write_concurrency, true}, {:read_concurrency, true}, :public])
      end)
      {:ok, state}
    end
  end


  @metrics [:reductions, :memory]
  def metrics, do: @metrics

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    Plug.Conn.register_before_send(conn, &store_metrics/1)
  end

  defp store_metrics(conn) do
    path = path_for(conn)

    :erlang.process_info(self(), metrics)
    |> Enum.each(fn {metric, val} ->
      :ets.update_counter(metric, _key = {path, :total_amount}, _increment = val, _default = {{path, :total_amount}, 0})
      :ets.update_counter(metric, _key = {path, :req_count}, _increment = 1, _default = {{path, :req_count}, 0})
    end)

    conn
  end

  def all_paths do
    metrics
    |> hd
    |> :ets.tab2list
    |> Enum.map(fn {{path, _}, _} -> path end)
    |> Enum.uniq
    |> Enum.sort
  end

  def metrics_for_current_path(conn) do
    path_for(conn)
    |> metrics_for_path
  end

  def metrics_for_path(path) do
    metrics
    |> Enum.map(fn metric ->
      total_amount = :ets.lookup(metric, {path, :total_amount}) |> parse_metric
      req_count = :ets.lookup(metric, {path, :req_count}) |> parse_metric
      {metric, format_metric(metric, total_amount, req_count)}
    end)
    |> Enum.into(%{})
  end

  defp format_metric(_, _, 0), do: "NA"
  defp format_metric(:memory, total, count), do: "#{delimited(total / count)} bytes"
  defp format_metric(:reductions, total, count), do: "#{delimited(total / count)} reductions"
  defp format_metric(metric, total, count), do: "#{delimited(total / count)} #{metric}"
  defp delimited(n) do
    n
    |> round
    |> Integer.digits
    |> Enum.reverse
    |> Enum.map(&to_string/1)
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.intersperse(",")
    |> Enum.reverse
    |> Enum.join
  end

  defp parse_metric([]), do: 0
  defp parse_metric([{_, v}]), do: v

  def path_for(conn) do
    cnt = conn |> Phoenix.Controller.controller_module |> Module.split |> Enum.join(".")
    "#{cnt}##{Phoenix.Controller.action_name(conn)}"
  end
end
