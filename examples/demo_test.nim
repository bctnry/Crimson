import demo_clex

# execute:
#     nimble build
#     ./Crimson ./examples/demo.clex
#     nim c ./examples/demo_test.nim
#     ./examples/demo_test

let str = "baabaaabakaacdebaaaf"
let lexRes = str.lex
for t in lexRes:
  echo t, " ", str[t.st..<t.e]
