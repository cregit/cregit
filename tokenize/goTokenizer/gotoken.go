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
	//	"os"
	"flag"
)


func Scanner_Scan(src []byte, printPositions bool) {

  	// Initialize the scanner.
  	var s scanner.Scanner
  	fset := token.NewFileSet()                      // positions are relative to fset
  	file := fset.AddFile("", fset.Base(), len(src)) // register input "file"
  	s.Init(file, src, nil /* no error handler */, scanner.ScanComments)
	
        fmt.Printf("-:-\tbegin_unit\n");

  	// Repeated calls to Scan yield the token sequence found in the input.
  	for {
  		pos, tok, lit := s.Scan()
  		if tok == token.EOF {
  			break
  		}
		var position = ""
		var tokenVal = ""

		if (printPositions) {
			position = fmt.Sprintf("%s\t", fset.Position(pos))
		}
		if (lit == "\n") {
			lit = "<newline>"
		}
		if (lit == "\r") {
			lit = "<return>"
		}

		if (lit == "" ) {
			tokenVal = fmt.Sprintf("%s", tok)
		} else {
			tokenVal = fmt.Sprintf("%s|%s", tok, lit)	
		}
			

		fmt.Printf("%s%s\n", position, tokenVal)
        }
        if (printPositions) {
		fmt.Printf("-:-\tend_unit\n");
	} else {
		fmt.Printf("end_unit\n");
	}
  
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
	var filename string
	
	printPositions := flag.Bool("p", false, "print positions")

	flag.Parse()

	filename = flag.Arg(0);


        fmt.Print(*printPositions, "\n");
        fmt.Print(filename);


	dat, err := ioutil.ReadFile(filename)

	check(err)

	Scanner_Scan(dat, *printPositions)
}

