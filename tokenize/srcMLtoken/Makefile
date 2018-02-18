default: srcml2token

srcml2token: srcml2token.cpp srcml2tokenHandlers.cpp srcml2tokenHandlers.hpp srcml2token.hpp
	g++ -g -std=c++11 -O -Wall -pedantic -o srcml2token srcml2token.cpp srcml2tokenHandlers.cpp  -lxerces-c-3.1

test: srcml2token
	srcml --position --language Java tests/StringUtil.java | ./srcml2token > tests/out/StringUtil.java.token
	diff tests/expected/StringUtil.java.token tests/out/StringUtil.java.token
	srcml --position --language C tests/audit.c | ./srcml2token > tests/out/audit.c.token
	diff tests/expected/audit.c.token tests/out/audit.c.token
	srcml --position --language C++ tests/ceiling.cpp | ./srcml2token > tests/out/ceiling.cpp.token
	diff tests/expected/ceiling.cpp.token tests/out/ceiling.cpp.token
	srcml --position --language C tests/main.c | ./srcml2token > tests/out/main.c.token
	diff tests/expected/main.c.token tests/out/main.c.token


expected: tests/srcml2tokenHandlers.cpp
	srcml --position --language 'C++' tests/srcml2tokenHandlers.cpp | ./srcml2token > tests/expected/srcml2tokenHandlers.cpp.token
	srcml --position --language C tests/main.c | ./srcml2token > tests/expected/main.c.token
	srcml --position --language 'C++' tests/ceiling.cpp | ./srcml2token > tests/expected/ceiling.cpp.token
	srcml --position --language C tests/audit.c | ./srcml2token > tests/expected/audit.c.token
	srcml --position --language Java tests/StringUtil.java | ./srcml2token > tests/expected/StringUtil.java.token

