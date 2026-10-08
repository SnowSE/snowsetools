defmodule SnowSeTools.Curriculum.XlsxReader do
  @moduledoc """
  Reads the cell values out of an .xlsx workbook, enough for the ABET matrix:
  sheet names, and each sheet as a grid of strings. Formatting, formulas and
  dates are ignored; a formula cell yields its cached value.

  An .xlsx is a zip of XML parts, so this needs only `:zip` and `:xmerl`.
  """

  require Record

  Record.defrecordp(
    :xml_element,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :xml_attribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(:xml_text, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))

  @type sheet :: %{name: String.t(), rows: [[String.t()]]}

  @spec read(binary()) :: {:ok, [sheet()]} | {:error, String.t()}
  def read(xlsx_binary) when is_binary(xlsx_binary) do
    with {:ok, parts} <- unzip(xlsx_binary),
         {:ok, workbook} <- fetch_part(parts, "xl/workbook.xml"),
         {:ok, rels} <- fetch_part(parts, "xl/_rels/workbook.xml.rels") do
      shared_strings = parts |> Map.get("xl/sharedStrings.xml") |> shared_strings()
      targets = relationship_targets(rels)

      sheets =
        workbook
        |> parse_xml()
        |> elements("sheet")
        |> Enum.map(fn sheet ->
          path = "xl/" <> String.trim_leading(targets[attribute(sheet, :"r:id")] || "", "/xl/")
          %{name: attribute(sheet, :name), rows: sheet_rows(parts[path], shared_strings)}
        end)

      {:ok, sheets}
    end
  rescue
    exception ->
      {:error,
       "That file could not be read as an .xlsx workbook (#{Exception.message(exception)})."}
  catch
    :exit, reason ->
      {:error, "That file could not be read as an .xlsx workbook (#{inspect(reason)})."}
  end

  defp unzip(binary) do
    case :zip.unzip(binary, [:memory]) do
      {:ok, files} -> {:ok, Map.new(files, fn {name, data} -> {to_string(name), data} end)}
      {:error, _reason} -> {:error, "That file is not an .xlsx workbook."}
    end
  end

  defp fetch_part(parts, name) do
    case Map.fetch(parts, name) do
      {:ok, data} -> {:ok, data}
      :error -> {:error, "The workbook is missing #{name}."}
    end
  end

  defp relationship_targets(rels_xml) do
    rels_xml
    |> parse_xml()
    |> elements("Relationship")
    |> Map.new(&{attribute(&1, :Id), attribute(&1, :Target)})
  end

  defp shared_strings(nil), do: {}

  defp shared_strings(xml) do
    xml
    |> parse_xml()
    |> elements("si")
    |> Enum.map(fn si -> si |> elements("t") |> Enum.map_join(&text/1) end)
    |> List.to_tuple()
  end

  defp sheet_rows(nil, _shared_strings), do: []

  defp sheet_rows(xml, shared_strings) do
    xml
    |> parse_xml()
    |> elements("row")
    |> Enum.map(fn row ->
      cells =
        row
        |> elements("c")
        |> Map.new(fn cell ->
          {column_index(attribute(cell, :r)), cell_value(cell, shared_strings)}
        end)

      width = if cells == %{}, do: 0, else: Enum.max(Map.keys(cells)) + 1
      Enum.map(0..(width - 1)//1, &Map.get(cells, &1, ""))
    end)
  end

  defp cell_value(cell, shared_strings) do
    case attribute(cell, :t) do
      "s" ->
        case cell |> elements("v") |> List.first() do
          nil -> ""
          v -> elem(shared_strings, v |> text() |> String.to_integer())
        end

      "inlineStr" ->
        cell |> elements("t") |> Enum.map_join(&text/1)

      _number_or_cached_formula ->
        cell |> elements("v") |> Enum.map_join(&text/1)
    end
    |> String.trim()
  end

  # "AB12" → 27 (zero-based column)
  defp column_index(reference) do
    reference
    |> String.replace(~r/\d+/, "")
    |> String.to_charlist()
    |> Enum.reduce(0, fn letter, acc -> acc * 26 + (letter - ?A + 1) end)
    |> Kernel.-(1)
  end

  defp parse_xml(binary) do
    {document, _rest} =
      :xmerl_scan.string(:binary.bin_to_list(binary), quiet: true, space: :normalize)

    document
  end

  # Every element named `name` below `node`, in document order. Names are
  # compared without their namespace prefix.
  defp elements(node, name) do
    node
    |> xml_element(:content)
    |> Enum.flat_map(fn
      child when Record.is_record(child, :xmlElement) ->
        if local_name(child) == name, do: [child], else: elements(child, name)

      _text ->
        []
    end)
  end

  defp local_name(element) do
    element |> xml_element(:name) |> to_string() |> String.split(":") |> List.last()
  end

  defp attribute(element, name) do
    element
    |> xml_element(:attributes)
    |> Enum.find_value(fn attr ->
      if xml_attribute(attr, :name) == name, do: attr |> xml_attribute(:value) |> to_string()
    end)
  end

  defp text(element) do
    element
    |> xml_element(:content)
    |> Enum.map_join(fn
      node when Record.is_record(node, :xmlText) -> node |> xml_text(:value) |> to_string()
      node when Record.is_record(node, :xmlElement) -> text(node)
      _other -> ""
    end)
  end
end
