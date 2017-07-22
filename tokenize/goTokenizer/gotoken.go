// This program was based on the example that is part of go:
//
// go/scanner/example_test.go
//
// with  Copyright 2012 The Go Authors and originally licensed
// as go (BSD style license).
// 
// Further modifications by daniel german
// 
  
package main
  
import (
   "fmt"
   "go/scanner"
   "go/token"
   "io/ioutil"
   "os"
)

var VERSION="1.0.0"
var CREGIT_VERSION="0.0.1"


  
    func Scanner_Scan(src []byte) {

  	// Initialize the scanner.
  	var s scanner.Scanner
  	fset := token.NewFileSet()                      // positions are relative to fset
  	file := fset.AddFile("", fset.Base(), len(src)) // register input "file"
  	s.Init(file, src, nil /* no error handler */, scanner.ScanComments)

        fmt.Printf("-:-\tbegin_unit|language=go;version=%s;cregit-version=%s\n", VERSION, CREGIT_VERSION);

  	// Repeated calls to Scan yield the token sequence found in the input.
  	for {
  		pos, tok, lit := s.Scan()
  		if tok == token.EOF {
  			break
  		}
                if (lit == "") {
                   fmt.Printf("%s\t%s\n", fset.Position(pos), tok)
                } else {
                   fmt.Printf("%s\t%s|%q\n", fset.Position(pos), tok, lit)
                }

        }
        
        fmt.Printf("-:-\tend_unit\n");
  
  	// output:
  	// 1:1	IDENT	"cos"
  	// 1:4	(	""
  	// 1:5	IDENT	"x"
  	// 1:6	)	""
  	// 1:8	+	""
  	// 1:10	IMAG	"1i"
  	// 1:12	*	""
  	// 1:13	IDENT	"sin"
  	// 1:16	(	""
  	// 1:17	IDENT	"x"
  	// 1:18	)	""
  	// 1:20	;	"\n"
  	// 1:20	COMMENT	"// Euler"
  }
  
func check(e error) {
    if e != nil {
        panic(e)
    }
}

func main() {

    dat, err := ioutil.ReadFile(os.Args[1])

    check(err)

    Scanner_Scan(dat)
}
