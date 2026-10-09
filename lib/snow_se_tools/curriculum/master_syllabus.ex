defmodule SnowSeTools.Curriculum.MasterSyllabus do
  @moduledoc """
  Reads a course's approved master syllabus from snow.edu.

  The site has no API, but its pages are rendered on the server: the course
  page (`course.html?subj_code=SE&crse_numb=3140`) links to the syllabus page
  (`syllabus.html?q=5757`), which lists the division, prerequisites, review
  dates and the learning outcomes. Outcomes the department has mapped to ABET
  carry a tag such as "(ABET SLO 2)".
  """

  require Logger

  @default_base_url "https://snow.edu/academics/science_math/engineering/se"
  @user_agent "Mozilla/5.0 (compatible; SnowSeTools/1.0)"
  @boilerplate ~r/^\s*upon successful completion of this course,?\s+(the\s+)?students?\s+will\s+be\s+able\s+to:?\s*/i

  def fetch(subject_code: subject_code, course_number: course_number) do
    with {:ok, course_html} <-
           get("course.html", subj_code: subject_code, crse_numb: course_number),
         {:ok, syllabus_id} <- parse_course_page(course_html),
         {:ok, syllabus_html} <- get("syllabus.html", q: syllabus_id),
         {:ok, syllabus} <- parse_syllabus_page(syllabus_html) do
      {:ok,
       Map.merge(syllabus, %{
         "snow_syllabus_id" => syllabus_id,
         "url" => "#{base_url()}/syllabus.html?q=#{syllabus_id}"
       })}
    end
  end

  def course_url(subject_code: subject_code, course_number: course_number) do
    "#{base_url()}/course.html?" <>
      URI.encode_query(crse_numb: course_number, subj_code: subject_code)
  end

  @doc "The master syllabus id the course page links to."
  def parse_course_page(html) when is_binary(html) do
    case Regex.run(~r/syllabus\.html\?q=(\d+)/, html) do
      [_full, id] -> {:ok, id}
      nil -> {:error, "snow.edu lists no master syllabus for this course."}
    end
  end

  @doc """
  The parts of a master syllabus page the curriculum map uses. Sections are
  found by their headings, so a section the page leaves out comes back empty
  rather than failing the whole read.
  """
  def parse_syllabus_page(html) when is_binary(html) do
    case find_body_content(:mochiweb_html.parse(html)) do
      nil ->
        {:error, "The syllabus page did not have the expected layout."}

      {_tag, _attrs, children} ->
        fields = labeled_fields(children)
        sections = sections(children)

        {:ok,
         %{
           "title" => children |> find_first("h3") |> text_of(),
           "prerequisites" => Map.get(fields, "prerequisites", ""),
           "corequisites" => Map.get(fields, "corequisites", ""),
           "semester_approved" => Map.get(fields, "semester approved", ""),
           "five_year_review" => Map.get(fields, "five-year review semester", ""),
           "description" => section_text(sections, "course description"),
           "content" => section_text(sections, "course content"),
           "outcomes" => section_items(sections, "student learning outcomes")
         }}
    end
  rescue
    exception ->
      Logger.error("Master syllabus page could not be parsed: #{Exception.message(exception)}")
      {:error, "The syllabus page could not be parsed."}
  end

  @doc "ABET student outcome numbers an outcome is tagged with, e.g. \"(ABET SLO 1, 2)\"."
  def abet_slos(outcome_text) do
    ~r/ABET\s*(?:SLOs?|SOs?|student\s+outcomes?)?\s*#?\s*([\d\s,&and]+)/i
    |> Regex.scan(outcome_text)
    |> Enum.flat_map(fn [_full, numbers] -> Regex.scan(~r/\d+/, numbers) end)
    |> Enum.map(fn [number] -> String.to_integer(number) end)
    |> Enum.filter(&(&1 in 1..7))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "The outcome without the \"Upon successful completion…\" lead-in every one of them repeats."
  def display_outcome(text) do
    case Regex.replace(@boilerplate, text, "") do
      "" -> text
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
    end
  end

  @doc "The outcome without its \"(ABET SLO 2)\" tag, for pages that show the tag as a badge."
  def without_abet_tag(text) do
    text
    |> String.replace(~r/\s*\(\s*ABET[^)]*\)/i, "")
    |> String.trim()
  end

  @doc "The form two outcome texts are compared in, so whitespace and case edits are not drift."
  def normalize_outcome(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end

  defp get(page, params) do
    url = "#{base_url()}/#{page}"

    options =
      [
        params: params,
        receive_timeout: 15_000,
        retry: :transient,
        headers: [{"user-agent", @user_agent}]
      ] ++ Application.get_env(:snow_se_tools, :curriculum_req_options, [])

    case Req.get(url, options) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("snow.edu answered #{status} for #{page} params=#{inspect(params)}")
        {:error, "snow.edu answered #{status} for #{page}."}

      {:error, exception} ->
        Logger.warning("snow.edu request failed page=#{page} reason=#{inspect(exception)}")
        {:error, "Could not reach snow.edu: #{Exception.message(exception)}"}
    end
  end

  defp base_url do
    Application.get_env(:snow_se_tools, :curriculum_master_syllabus_base_url, @default_base_url)
  end

  defp find_body_content({_tag, attrs, children} = node) when is_list(children) do
    if has_class?(attrs, "body-content") do
      node
    else
      Enum.find_value(children, &find_body_content/1)
    end
  end

  defp find_body_content(_leaf), do: nil

  defp has_class?(attrs, class) do
    Enum.any?(attrs, fn {name, value} ->
      name == "class" and class in String.split(value)
    end)
  end

  # "<li><b>Prerequisites</b>: CS 2450 and CS 2860</li>" → %{"prerequisites" => "CS 2450 and CS 2860"}
  defp labeled_fields(nodes) do
    nodes
    |> all_elements("li")
    |> Enum.flat_map(fn {_tag, _attrs, children} ->
      case children do
        [{"b", _b_attrs, label} | rest] ->
          key = label |> text_of() |> String.trim_trailing(":") |> String.downcase()
          value = rest |> text_of() |> String.trim_leading(":") |> String.trim()
          [{key, value}]

        _no_label ->
          []
      end
    end)
    |> Map.new()
  end

  # The page is a flat run of <h4>Heading</h4> followed by that section's
  # nodes, so a section is everything up to the next <h4>.
  defp sections(children) do
    children
    |> Enum.reduce({nil, %{}}, fn
      {"h4", _attrs, heading}, {_current, acc} ->
        key = heading |> text_of() |> String.downcase()
        {key, Map.put(acc, key, [])}

      node, {current, acc} when is_binary(current) ->
        {current, Map.update!(acc, current, &[node | &1])}

      _before_first_heading, state ->
        state
    end)
    |> elem(1)
    |> Map.new(fn {key, nodes} -> {key, Enum.reverse(nodes)} end)
  end

  defp section_text(sections, key) do
    sections
    |> Map.get(key, [])
    |> Enum.reject(&hidden?/1)
    |> text_of()
  end

  defp section_items(sections, key) do
    sections
    |> Map.get(key, [])
    |> all_elements("li")
    |> Enum.map(&text_of/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp hidden?({_tag, attrs, _children}),
    do: Enum.any?(attrs, fn {name, _value} -> name == "hidden" end)

  defp hidden?(_text), do: false

  defp find_first(nodes, tag), do: nodes |> all_elements(tag) |> List.first()

  defp all_elements(nodes, tag) when is_list(nodes),
    do: Enum.flat_map(nodes, &all_elements(&1, tag))

  defp all_elements({tag, _attrs, children} = node, tag) when is_list(children),
    do: [node | all_elements(children, tag)]

  defp all_elements({_other, _attrs, children}, tag) when is_list(children),
    do: all_elements(children, tag)

  defp all_elements(_leaf, _tag), do: []

  defp text_of(nil), do: ""

  defp text_of(nodes) do
    nodes
    |> collect_text()
    |> IO.iodata_to_binary()
    |> String.replace(~r/[ \t\r\f\v\x{00A0}]+/u, " ")
    |> String.replace(~r/ *\n */, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp collect_text(text) when is_binary(text), do: text
  defp collect_text(nodes) when is_list(nodes), do: Enum.map(nodes, &collect_text/1)
  defp collect_text({"br", _attrs, _children}), do: "\n"
  defp collect_text({"script", _attrs, _children}), do: ""

  defp collect_text({tag, _attrs, children}) when tag in ["p", "li", "div", "h3", "h4"],
    do: [collect_text(children), "\n"]

  defp collect_text({_tag, _attrs, children}), do: collect_text(children)
  defp collect_text(_comment_or_other), do: ""
end
