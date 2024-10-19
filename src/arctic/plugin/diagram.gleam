import arctic/parse
import gleam/bool
import gleam/dict
import gleam/int
import gleam/result.{map_error}
import lustre/attribute
import lustre/element/html
import shellout
import simplifile
import snag

pub fn parse(dir: String, get_id: fn(a) -> Int, to_state: fn(Int) -> a) {
  fn(_args: List(String), body: String, data: parse.ParseData(a)) {
    // TODO: use pos for error messages
    let counter = get_id(parse.get_state(data))
    let assert Ok(id) = dict.get(parse.get_metadata(data), "id")
    let img_filename = "image-" <> int.to_string(counter) <> "-" <> id <> ".svg"
    let out = #(
      html.div([attribute.class("diagram")], [
        html.img([
          attribute.src("/" <> img_filename),
          attribute.attribute("onload", "this.width *= 2.25;"),
        ]),
      ]),
      to_state(counter + 1),
    )
    use exists <- result.try(
      simplifile.is_file(dir <> "/" <> img_filename)
      |> map_error(fn(err) {
        snag.new(
          "couldn't check `"
          <> dir
          <> "/"
          <> img_filename
          <> "` ("
          <> simplifile.describe_error(err)
          <> ")",
        )
      }),
    )
    // very simple caching: if we've generated an image with this name before, don't do it again
    // this works for now because I can always just delete an image file.
    // But in the future I want an actual caching system that detects updates.
    // Perhaps a sqlite db?
    use <- bool.guard(when: exists, return: Ok(out))
    let latex_code = "
\\documentclass[margin=0pt]{standalone}
\\usepackage{tikz-cd}
\\begin{document}
\\begin{tikzcd}\n" <> body <> "\\end{tikzcd}
\\end{document}"
    use _ <- result.try(
      simplifile.write(latex_code, to: "./diagram-work/diagram.tex")
      |> map_error(fn(err) {
        snag.new(
          "couldn't write to `diagram-work/diagram.tex` ("
          <> simplifile.describe_error(err)
          <> ")",
        )
      }),
    )
    use _ <- result.try(
      shellout.command(
        run: "pdflatex",
        with: ["-interaction", "nonstopmode", "diagram.tex"],
        in: "diagram-work",
        opt: [],
      )
      |> map_error(fn(err) {
        snag.new(
          "couldn't execute `pdflatex -interaction nonstopmode diagram.tex` in `diagram-work` (Code "
          <> int.to_string(err.0)
          <> ": "
          <> err.1,
        )
      }),
    )
    use _ <- result.try(
      shellout.command(
        run: "inkscape",
        with: [
          "-l",
          "--export-filename",
          "../" <> dir <> "/" <> img_filename,
          "diagram.pdf",
        ],
        in: "diagram-work",
        opt: [shellout.LetBeStdout],
      )
      |> map_error(fn(err) {
        snag.new(
          "couldn't execute `inkscape -l --export-filename ../"
          <> dir
          <> "/"
          <> img_filename
          <> " diagram.pdf` in `diagram-work` (Code "
          <> int.to_string(err.0)
          <> ": "
          <> err.1
          <> ")",
        )
      }),
    )
    Ok(out)
  }
}
