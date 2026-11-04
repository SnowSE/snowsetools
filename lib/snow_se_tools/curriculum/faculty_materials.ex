defmodule SnowSeTools.Curriculum.FacultyMaterials do
  @moduledoc """
  Course materials from the SnowSE/faculty repository, which is where skills
  like "git from the command line" or "mocks & fakes" actually show up: the
  master syllabus says what a course is for, the lectures and assignments say
  what students do.

  The repository is laid out as `<course folder>/<term folder>/…`, e.g.
  `3820_BackEnd/2026-fall-dallan/modules/…`. For each course this reads the
  markdown in the folders of its three most recent terms (every instructor's
  folder for those terms), most informative files first, up to a size budget
  the model's context can hold.

  The repository is private, so this needs a read-only GitHub token
  (`CURRICULUM_GITHUB_TOKEN`). Without one it reports itself not configured
  and the review runs on the other sources.
  """

  require Logger

  alias SnowSeTools.Curriculum.TermLabel

  @api "https://api.github.com"
  @terms_to_read 3
  @max_files 60
  @max_file_bytes 60_000
  @priority ~r/(syllabus|course[-_ ]?plan|overview|topics?|outline|schedule|plans?|readme)/i
  @readable ~r/\.(md|markdown|txt)$/i

  def configured?, do: token() not in [nil, ""]

  @doc """
  The repository's file tree, fetched once per review run and shared by every
  course.
  """
  def fetch_tree do
    if configured?() do
      case request("/repos/#{repo()}/git/trees/HEAD", params: [recursive: 1]) do
        {:ok, %{"tree" => entries} = body} ->
          if body["truncated"],
            do: Logger.warning("Faculty repository tree was truncated by GitHub")

          {:ok, entries}

        {:ok, other} ->
          {:error, "GitHub returned an unexpected tree: #{inspect(other, limit: 5)}"}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_configured}
    end
  end

  @doc """
  The markdown for one course, as one text block with a heading per file,
  capped at `budget` characters. Answers the folders read so the run can say
  where its evidence came from.
  """
  def read_course(tree: tree, course_number: course_number, budget: budget) do
    files = select_files(tree: tree, course_number: course_number)

    {texts, _remaining} =
      Enum.reduce_while(files, {[], budget}, fn file, {texts, remaining} ->
        if remaining <= 0 do
          {:halt, {texts, remaining}}
        else
          case fetch_blob(file["sha"]) do
            {:ok, content} ->
              chunk = "### #{file["path"]}\n#{String.slice(content, 0, remaining)}"
              {:cont, {[chunk | texts], remaining - String.length(chunk)}}

            {:error, reason} ->
              Logger.warning(
                "Faculty file skipped path=#{file["path"]} reason=#{inspect(reason)}"
              )

              {:cont, {texts, remaining}}
          end
        end
      end)

    {:ok,
     %{
       text: texts |> Enum.reverse() |> Enum.join("\n\n"),
       folders: files |> Enum.map(&term_folder(&1["path"])) |> Enum.uniq()
     }}
  end

  @doc """
  The files worth reading for a course: markdown under the term folders of
  its most recent terms, plans and overviews first. Pure, so the folder rules
  can be tested without GitHub.
  """
  def select_files(tree: tree, course_number: course_number) do
    term_folders =
      tree
      |> Enum.filter(&(&1["type"] == "tree"))
      |> Enum.map(& &1["path"])
      |> Enum.filter(&term_folder_of_course?(&1, course_number))
      |> then(
        &TermLabel.latest(
          items: &1,
          count: @terms_to_read,
          label: fn path -> Path.basename(path) end
        )
      )
      |> MapSet.new()

    tree
    |> Enum.filter(fn entry ->
      entry["type"] == "blob" and Regex.match?(@readable, entry["path"]) and
        (entry["size"] || 0) <= @max_file_bytes and
        MapSet.member?(term_folders, term_folder(entry["path"]))
    end)
    |> Enum.sort_by(fn entry ->
      {if(Regex.match?(@priority, Path.basename(entry["path"])), do: 0, else: 1),
       path_depth(entry["path"]), entry["path"]}
    end)
    |> Enum.take(@max_files)
  end

  defp term_folder_of_course?(path, course_number) do
    case Path.split(path) do
      [course_folder, term_folder] ->
        course_folder?(course_folder, course_number) and
          match?({:ok, _}, TermLabel.parse(term_folder))

      _other_depth ->
        false
    end
  end

  # "3820_BackEnd" and "4450" are 3820 and 4450; "1400_engr" is the
  # engineering department's version of the course, not ours.
  defp course_folder?(folder, course_number) do
    Regex.match?(~r/^#{Regex.escape(course_number)}(?:$|[_\- ])/, folder) and
      not Regex.match?(~r/engr/i, folder)
  end

  defp term_folder(path), do: path |> Path.split() |> Enum.take(2) |> Path.join()

  defp path_depth(path), do: path |> Path.split() |> length()

  defp fetch_blob(sha) do
    case request("/repos/#{repo()}/git/blobs/#{sha}", []) do
      {:ok, %{"content" => content, "encoding" => "base64"}} ->
        case content |> String.replace(~r/\s/, "") |> Base.decode64() do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:error, :bad_base64}
        end

      {:ok, other} ->
        {:error, {:unexpected_blob, Map.take(other, ["encoding", "message"])}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(path, options) do
    options =
      [
        headers: [
          {"authorization", "Bearer #{token()}"},
          {"accept", "application/vnd.github+json"},
          {"x-github-api-version", "2022-11-28"}
        ],
        receive_timeout: 30_000,
        retry: :transient
      ] ++ options ++ Application.get_env(:snow_se_tools, :curriculum_req_options, [])

    case Req.get(@api <> path, options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        message = if is_map(body), do: body["message"], else: nil
        {:error, "GitHub answered #{status}#{if message, do: ": #{message}"}"}

      {:error, exception} ->
        {:error, "Could not reach GitHub: #{Exception.message(exception)}"}
    end
  end

  defp token, do: Application.get_env(:snow_se_tools, :curriculum, [])[:github_token]

  defp repo,
    do: Application.get_env(:snow_se_tools, :curriculum, [])[:faculty_repo] || "SnowSE/faculty"
end
