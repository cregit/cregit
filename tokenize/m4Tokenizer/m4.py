#!/usr/bin/env python

import itertools
import sys

from collections import defaultdict


class ParseError(Exception):
    def __init__(self, message):
        self.message = message

    def __str__(self):
        return 'ParseError(%s)' % self.message


class Token(object):
    def __init__(self, name, value=None):
        self.type = name
        self.value = name if value is None else value

    def __eq__(self, other):
        if isinstance(other, Token):
            return self.type == other.type and self.value == other.value
        return False

    def __repr__(self):
        return "<Token: %r %r>" % (self.type, self.value)


class eof(str):
    def __repr__(self):
        return '<EOF>'


EOF = eof()


def endswith(l, e):
    return l[-len(e):] == e


def name(x):
    return x.__name__ if hasattr(x, '__name__') else x


class peek_insert_iter:
    def __init__(self, iter):
        self.iter = iter
        self.inserted = []
        self.peeked = []

    def __iter__(self):
        return self

    def next(self):
        if self.inserted:
            return self.inserted.pop(0)
        if self.peeked:
            return self.peeked.pop(0)
        return self.iter.next()

    def insert(self, iterable):
        self.inserted[0:0] = iterable

    def _peek(self):
        if not self.peeked:
            try:
                self.peeked.append(self.iter.next())
            except StopIteration:
                pass

    def peek(self):
        if self.inserted:
            return self.inserted[0]
        self._peek()
        if self.peeked:
            return self.peeked[0]
        return EOF


class Lexer:
    def __init__(self, text):
        self.text = text
        self.state = None
        self.chars = []
        self.nesting_level = 0
        self.start_quote = ['`']
        self.end_quote = ["'"]
        self.iter = None

    def _finish_token(self, name):
        t = Token(name, ''.join(self.chars))
        self.chars = []
        return t

    def insert_text(self, text):
        self.iter.insert(text)

    def changequote(self, start_quote='`', end_quote='\''):
        self.start_quote = [start_quote]
        self.end_quote = [end_quote]

    def parse(self):
        '''
        Return an iterator that produces tokens. The iterator
        has one extra method: peek_char, that allows consumers
        to peek at the next character before it is lexed.
        '''
        lexer = self

        class peekthrough_iter:
            def __init__(self, iter):
                self.iter = iter

            def __iter__(self):
                return self.iter

            def next(self):
                return self.iter.next()

            def peek_char(self):
                return lexer.iter.peek()
        self.iter = peek_insert_iter(iter(self.text))
        return peekthrough_iter(self._parse_internal())

    def _parse_internal(self):
        while True:
            c = self.iter.peek()
            #print 'CHAR: %s (state: %s)' % (repr(c), name(self.state))
            if self.state is not None:
                tokens = self.state(c)
            else:
                tokens = self._generic(c)
            for tok in tokens:
                yield tok
            if c is EOF and self.iter.peek() is EOF:
                break
        if self.chars:
            if self.state is None:
                for c in self.chars:
                    yield Token(c, c)
            else:
                raise ParseError('Error, unterminated %s' % name(self.state))

    def _generic(self, c):
        if c is not EOF:
            self.chars.append(self.iter.next())
        if c.isalpha() or c == '_':
            self.state = self._identifier
        elif c == '#':
            self.state = self._comment
        # TODO: handle multi-character quotes
        if self.chars == self.start_quote:
            self.state = self._string
            self.nesting_level = 1
        if self.state is None:
            tokens = [Token(c, c) for c in self.chars]
            self.chars = []
            return tokens
        return []

    def _string(self, c):
        self.chars.append(self.iter.next())
        if (
                self.start_quote != self.end_quote and
                endswith(self.chars, self.start_quote)
        ):
            self.nesting_level += 1
        elif endswith(self.chars, self.end_quote):
            self.nesting_level -= 1
            if self.nesting_level == 0:
                # strip start/end quote out of the token value
                self.chars = \
                    self.chars[len(self.start_quote):-len(self.end_quote)]
                self.state = None
                return [self._finish_token('STRING')]
        return []

    def _identifier(self, c):
        if not (c.isalnum() or c == '_'):
            self.state = None
            return [self._finish_token('IDENTIFIER')]

        self.chars.append(self.iter.next())
        return []

    def _comment(self, c):
        if c != '\n' and c is not EOF:
            self.chars.append(self.iter.next())
            return []

        self.state = None
        return [self._finish_token('COMMENT')]


def substmacro(name, body, args):
    # TODO: implement argument substitution
    return body


class Parser:
    def __init__(self, text):
        self.macros = {
            'define': self._builtin_define,
            'dnl': self._builtin_dnl,
            'changequote': self._builtin_changequote,
            'divert': self._builtin_divert,
        }
        self.lexer = Lexer(text)
        self.token_iter = self.lexer.parse()
        self.diversions = defaultdict(list)
        self.current_diversion = 0

    def _builtin_define(self, args):
        if args:
            self.define(*args[:2])
        return None

    def _builtin_dnl(self, args):
        # Eat tokens till newline
        for tok in self.token_iter:
            if tok.value == '\n':
                break
        return None

    def _builtin_changequote(self, args):
        self.changequote(*args[:2])
        return None

    def _builtin_divert(self, args):
        args = args or [0]
        try:
            self.current_diversion = int(args[0])
        except ValueError:
            # GNU m4 prints a warning here:
            # m4:stdin:1: non-numeric argument to builtin `divert'
            return
        return None

    def _parse_args(self):
        args = []
        current_arg = []
        if self.token_iter.peek_char() == '(':
            # drop that token
            tok = self.token_iter.next()
            if tok.value != '(':
                raise ParseError('Expected open parenthesis but got %s'
                                 % tok.value)
            nesting_level = 1
            for tok in self._expand_tokens():
                if tok.value == '(':
                    nesting_level += 1
                elif tok.value == ',' or tok.value == ')':
                    args.append(''.join(current_arg))
                    current_arg = []
                elif current_arg or not tok.value.isspace():
                    current_arg.append(tok.value)
                if tok.value == ')':
                    nesting_level -= 1
                    if nesting_level == 0:
                        break
            # TODO: handle EOF without closing paren
        return args

    def _expand_tokens(self):
        for tok in self.token_iter:
            if (
                    isinstance(tok, Token)
                    and tok.type == 'IDENTIFIER'
                    and tok.value in self.macros
            ):
                result = self.macros[tok.value](self._parse_args())
                if result:
                    self.lexer.insert_text(result)
            else:
                yield tok

    def define(self, name, body=''):
        self.macros[name] = lambda x: substmacro(name, body, x)

    def changequote(self, start_quote='`', end_quote='\''):
        self.lexer.changequote(start_quote, end_quote)

    def parse(self, stream=sys.stdout):
        for tok in self._expand_tokens():
            print tok
#            if self.current_diversion == 0:
#                stream.write(tok.value)
#            elif self.current_diversion > 0:
#                self.diversions[self.current_diversion].append(tok.value)
#        for diversion in sorted(self.diversions.keys()):
#            if diversion < 1:
##                continue
#            stream.write(''.join(self.diversions[diversion]))
#            self.diversions[diversion] = []


if __name__ == '__main__':
    Parser(sys.stdin.read()).parse()
