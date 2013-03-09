debug = -> null #(n...) -> console.log n

output = $('#output')
input  = $('#input')

io = {
  start: -> null,
  get: (a, cb) ->
    io.out "input:"
    input.keypress (e) ->
      if e.which == 13
        value = input.val()
        input.val ""
        input.off "keypress"
        io.out value+"\n"
        cb false, { input : value }
      true
  out: (n) -> output.append n
}

data = create document.getElementById("image").text

piet_eval data

$("#run").click ->
  output.html ""
  piet_eval data
