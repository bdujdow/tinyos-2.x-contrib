{
import java.io.*;
import java.util.*;

import antlr.CommonAST;
import antlr.DumpASTVisitor;
}class GnuCEmitter extends TreeParser;

options {
	importVocab= GNUC;
	buildAST= false;
	ASTLabelType= "TNode";
	codeGenMakeSwitchThreshold= 2;
	codeGenBitsetTestThreshold= 3;
}

{
String p2="";
String l2="";
public int dirCnt=0;
private String a;
private String func_name;
private String prevF="";
private String path;
private String path_func;
private boolean loopFlag = false;
private boolean loop2Flag = false;
private boolean loopInsideFlag = false;
private String printString ="";
private String printString2 ="";
private String line;
private String line_func;
private String lineDir;
private String previousLine="";
private String previousPath="";
private boolean check = false;
private boolean check_func = false;
private boolean x = false;
public AsmParser  asmP;
public String[] paths = new String[100];
public String[] lines = new String[100];
public boolean isFunction = false;
public String forReturn;
public String forWhile;
public Boolean returnAlert=false;
int tabs = 0;
PrintStream currentOutput = System.out;
int lineNum = 1;
String currentSource = "";
LineObject trueSourceFile;
final int lineDirectiveThreshold = Integer.MAX_VALUE;
PreprocessorInfoChannel preprocessorInfoChannel = null;
Stack sourceFiles = new Stack();

GnuCEmitter( PreprocessorInfoChannel preprocChannel )
{
        preprocessorInfoChannel = preprocChannel;
	
}

void transform(){
String p="";
String l="";
String c;
SourceFile currF;
SourceLine  currL;
currF = asmP.fList.first;
int count=0;

if(!( (previousLine.compareTo(line) == 0)  && (previousPath.compareTo(path)==0) ) || (prevF.compareTo(func_name)!=0)){
	while(currF != null)
	{
		if((currF.path.compareTo(path) == 0) || (currF.component.compareTo(path)== 0))
		{
			String ct="";
			p = currF.path;
			currL = currF.line;
			while(currL != null)
			{
				if((currL.lineNum.compareTo(line) == 0) && (currL.inFunction.compareTo(func_name)==0))
				{
					l=currL.lineNum;
					count++;
					ct= "check_time(" + currL.numOfCycles + ");" ;
					previousLine = line;
					previousPath = path;
					prevF = func_name;
				}
				currL = currL.nextLine;
			}
			if(!(count > 1))
			{
				if(count == 1){
					System.out.println("");
					//System.out.println ("printf(\"" + p + ":" + l + "\\n\");");
					System.out.print(ct);
				}
				/*
				else{
					currL = currF.line;
					while(currL != null)
					{
				if((currL.lineNum.compareTo(line) == 0) && (currL.inFunction.compareTo(func_name)==0))
					{
					previousLine = line;
					previousPath = path;
					prevF = func_name;
					System.out.println("");
					System.out.print("check_time(" + currL.numOfCycles + ");");
		
					
					}
					currL = currL.nextLine;
					}
				}
				*/
			}
			else{
				boolean b = false;
				currL = currF.line;
				while(currL != null)
				{
				if((currL.lineNum.compareTo(line) == 0) && (currL.inFunction.compareTo(func_name)==0))
				{
					p2 = path;
					l2 = line;
					if(!b){
						b = true;
						printString =  String.valueOf(currL.numOfCycles);
						System.out.println("");
						System.out.print("check_time(" + (currL.numOfCycles) + ");");
						
					}
					else{
						printString +=  "+" + String.valueOf(currL.numOfCycles);
					}
					
				}
				currL = currL.nextLine;
				}
				loopFlag = true;
			}
			break;
		}
		currF = currF.nextFile;
	}
} 

}

void parseLine(int i){
	int sIndex;
	int eIndex;
	System.out.println();
	switch(i){

	case 1:
		if((sIndex = lineDir.indexOf("\"")) != -1){
			eIndex = lineDir.indexOf("\"",sIndex+1);
			paths[dirCnt] = lineDir.substring(sIndex+1,eIndex);
			lines[dirCnt++] = lineDir.substring(2,sIndex-1);
		}
		else{
			line = lineDir.substring(6);
		}
		break;
	case 2:
		if((sIndex = lineDir.indexOf("\"")) != -1){
			eIndex = lineDir.indexOf("\"",sIndex+1);
			path = lineDir.substring(sIndex+1,eIndex);
			line = lineDir.substring(2,sIndex-1);
			transform();
		}
		else{
			line = lineDir.substring(6);
			transform();
		}
		break;
	case 3:
		if((sIndex = lineDir.indexOf("\"")) != -1){
			eIndex = lineDir.indexOf("\"",sIndex+1);
			path_func = lineDir.substring(sIndex+1,eIndex);
			line_func = lineDir.substring(2,sIndex-1);
		}
		else{
			line = lineDir.substring(6);
		}
		break;
	
	default:
		break;
	}

}

void preTransform(){
	path=path_func;
	line=line_func;
	//System.out.println("function printing");
	transform();
}


/*
	public void adjustWhile(TNode cmp_AST){
		
		TNode node = (TNode)cmp_AST.getFirstChild();

		while(node != null){
			if(node.getType()==LITERAL_while){
				TNode dir = node.getPrevSibling();
				if (dir==null) {continue;}
				if (dir.getType() == PREPROC_DIRECTIVE){
					TNode dir2 = new TNode();
					//dir.removeSelf();
					//dir.makeAlone();
					dir2.initialize(dir);
					//node.addSibling(dir2);
					TNode curr = (TNode)node.getFirstChild();
					while(curr!=null){
						if(curr.getType() == NCompoundStatement){
							//TNode temp = (TNode)curr.getFirstChild();
							//curr.removeChildren();
							//curr.addChild(dir);
							((TNode)curr.getLastChild()).addSiblingBefore(dir2);
							dir2.setLineNum(((TNode)dir2.getNextSibling()).getLineNum()-1);
							break;
						}
						curr=(TNode)curr.getNextSibling();
					}
				}
			}
			if(node.getType()==LITERAL_switch){
				TNode dir = node.getPrevSibling();
				if (dir==null) {continue;}
				if (dir.getType() == PREPROC_DIRECTIVE){
					int sIndex;
					int eIndex;
					String linedir;
					String ps;
					String ls;
					SourceFile currf;
					SourceLine  currl;
					currf = asmP.fList.first;
					linedir = dir.getText();
					if((sIndex = linedir.indexOf("\"")) != -1){
						eIndex = linedir.indexOf("\"",sIndex+1);
						ps = linedir.substring(sIndex+1,eIndex);
						ls = linedir.substring(2,sIndex-1);
						
						while(currf != null)
						{
							if((currf.path.compareTo(ps) == 0) )
							{
								currl = currf.line;
								while(currl != null){
								   if(currl.lineNum.compareTo(ls) == 0){
								       currl.numOfCycles = (currl.numOfCycles * 3) / 4;
								       break;
								   }
									currl = currl.nextLine;		
								}
								break;
							}
							currf = currf.nextFile;
						}
					}
				}
			}
			node = (TNode)node.getNextSibling();
		}
	}
*/

public void adjustWhile(TNode cmp_AST){
		
		TNode node = (TNode)cmp_AST.getFirstChild();

		while(node != null){
			if(node.getType()==LITERAL_while){
				TNode dir = node.getPrevSibling();
				if (dir==null) {node = (TNode)node.getNextSibling();continue;}
				if (dir.getType() == PREPROC_DIRECTIVE){
					TNode dir2 = new TNode();	
					TNode curr = (TNode)node.getFirstChild();
					while(curr!=null){
						if(curr.getType() == NCompoundStatement){

						   int sIndex;
					           int eIndex;
					           String linedir;
					           String ps;
						   String ls;
						   SourceFile currf;
						   SourceLine  currl;
						   currf = asmP.fList.first;
					 	   linedir = dir.getText();
						   if((sIndex = linedir.indexOf("\"")) != -1){
						     eIndex = linedir.indexOf("\"",sIndex+1);
						     ps = linedir.substring(sIndex+1,eIndex);
						     ls = linedir.substring(2,sIndex-1);
						
						     while(currf != null)
						     {
					if((currf.path.compareTo(ps) == 0) || (currf.component.compareTo(ps)== 0) )
						       {
							 currl = currf.line;
							 while(currl != null){
						  	   if(currl.lineNum.compareTo(ls) == 0){
						           TNode stmnt = new TNode();
							   TNode postFix = new TNode();
							   TNode id = new TNode();
							   TNode funcCall = new TNode();
							   TNode num= new TNode();
							   TNode par= new TNode();
							   stmnt.setType(NStatementExpr);
							   stmnt.addChild(postFix);
							   postFix.setType(NPostfixExpr);
							   postFix.addChild(id);
							   id.setType(ID);
							   id.setText("check_time");
							   id.addSibling(funcCall);
							   funcCall.setType(NFunctionCallArgs);
							   funcCall.setText("(");
							   funcCall.addChild(num);
							   num.setType(Number);
							   num.setText(Double.toString(currl.numOfCycles));
							   num.addSibling(par);
							   par.setType(RPAREN);
							   par.setText(")");
							 //stmnt.setLineNum(((TNode)curr.getLastChild()).getLineNum());
							   ((TNode)curr.getLastChild()).addSiblingBefore(stmnt);
						           break;
						         }
							   currl = currl.nextLine;		
							 }
							   break;
							 }
							   currf = currf.nextFile;
						      }
						     }

							//TNode temp = (TNode)curr.getFirstChild();
							//curr.removeChildren();
							//curr.addChild(dir);
							
						//dir2.setLineNum(((TNode)dir2.getNextSibling()).getLineNum()-1);
							//break;
						}
						curr=(TNode)curr.getNextSibling();
					}
				}
			}
			if(node.getType()==LITERAL_switch){
				
				TNode dir = node.getPrevSibling();
				if (dir==null) {continue;}
				if (dir.getType() == PREPROC_DIRECTIVE){
					
					int sIndex;
					int eIndex;
					String linedir;
					String ps;
					String ls;
					SourceFile currf;
					SourceLine  currl;
					currf = asmP.fList.first;
					linedir = dir.getText();
					if((sIndex = linedir.indexOf("\"")) != -1){
						eIndex = linedir.indexOf("\"",sIndex+1);
						ps = linedir.substring(sIndex+1,eIndex);
						ls = linedir.substring(2,sIndex-1);
						while(currf != null)
						{
					if((currf.path.compareTo(ps) == 0) || (currf.component.compareTo(ps)== 0))
							{
								
								currl = currf.line;
								while(currl != null){
								   if(currl.lineNum.compareTo(ls) == 0){
								       currl.numOfCycles = (currl.numOfCycles * 3) / 4;
								       break;
								   }
									currl = currl.nextLine;		
								}
								break;
							}
							currf = currf.nextFile;
						}
					}
				}
			}
			node = (TNode)node.getNextSibling();
		}
	}

	


public void adjustReturn(TNode cmp_AST){

	TNode node = (TNode)cmp_AST.getLastChild();
	TNode dir = node.getPrevSibling();
	if (dir==null) {return;}
	if (dir.getType() == PREPROC_DIRECTIVE){
		forReturn = dir.getText();
		returnAlert = true;
	}


    
}

public void directPrint(){

}


void initializePrinting()
{
    Vector preprocs = preprocessorInfoChannel.extractLinesPrecedingTokenNumber( new Integer(1) );
    printPreprocs(preprocs);
/*    if ( currentSource.equals("") ) {
        trueSourceFile = new LineObject(currentSource);
        currentOutput.println("# 1 \"" + currentSource + "\"\n");
        sourceFiles.push(trueSourceFile);
    } 
*/
}

void finalizePrinting() {
    // flush any leftover preprocessing instructions to the stream

    printPreprocs( 
        preprocessorInfoChannel.extractLinesPrecedingTokenNumber( 
                new Integer( preprocessorInfoChannel.getMaxTokenNumber() + 1 ) ));
    //print a newline so file ends at a new line
    currentOutput.println();
}

void printPreprocs( Vector preprocs ) 
{
    // if there was a preprocessingDirective previous to this token then
    // print a newline and the directive, line numbers handled later
    if ( preprocs.size() > 0 ) {  
        if ( trueSourceFile != null ) {
            currentOutput.println();  //make sure we're starting a new line unless this is the first line directive
        }
        lineNum++;
        Enumeration e = preprocs.elements();
        while (e.hasMoreElements())
        {
            Object o = e.nextElement();
            if ( o.getClass().getName().equals("LineObject") ) {
                LineObject l = (LineObject) o;

                // we always return to the trueSourceFile, we never enter it from another file
                // force it to be returning if in fact we aren't currently in trueSourceFile
                if (( trueSourceFile != null ) //trueSource exists
                        && ( !currentSource.equals(trueSourceFile.getSource()) ) //currently not in trueSource
                        && ( trueSourceFile.getSource().equals(l.getSource())  ) ) { //returning to trueSource
                    l.setEnteringFile( false );
                    l.setReturningToFile( true );
                }


                // print the line directive
                currentOutput.println(l);
                lineNum = l.getLine();
                currentSource = l.getSource();


                // the very first line directive always represents the true sourcefile
                if ( trueSourceFile == null ) {
                    trueSourceFile = new LineObject(currentSource);
                    sourceFiles.push(trueSourceFile);
                }

                // keep our own stack of files entered
                if ( l.getEnteringFile() ) {
                    sourceFiles.push(l);
                }

                // if returning to a file, pop the exited files off the stack
                if ( l.getReturningToFile() ) {
                    LineObject top = (LineObject) sourceFiles.peek();
                    while (( top != trueSourceFile ) && (! l.getSource().equals(top.getSource()) )) {
                        sourceFiles.pop();
                        top = (LineObject) sourceFiles.peek();
                    }
                }
            }
            else { // it was a #pragma or such
                currentOutput.println(o);
                lineNum++;
            }
        }
    }

}

void print( TNode t ) {
    int tLineNum = t.getLocalLineNum();
    if ( tLineNum == 0 ) tLineNum = lineNum;

    Vector preprocs = preprocessorInfoChannel.extractLinesPrecedingTokenNumber((Integer)t.getAttribute("tokenNumber"));
    printPreprocs(preprocs);
    
    if ( (lineNum != tLineNum) ) {
        // we know we'll be newlines or a line directive or it probably
        // is just the case that this token is on the next line
        // either way start a new line and indent it
        currentOutput.println();
        lineNum++;      
        printTabs();
    }

    if ( lineNum == tLineNum ){
        // do nothing special, we're at the right place
    }
    else {  
        int diff = tLineNum - lineNum;
        if ( lineNum < tLineNum ) {
            // print out the blank lines to bring us up to right line number
            for ( ; lineNum < tLineNum ; lineNum++ ) {
                currentOutput.println();
            }
            printTabs();
        }
        else { // just reset lineNum
            lineNum = tLineNum; 
        }
    }
    currentOutput.print( t.getText() + " " );
}


/* This was my attempt at being smart about line numbers
   It didn't work quite right but I don't know why, I didn't
   have enough test cases.  Worked ok compiling rcs and ghostscript
*/
void printAddingLineDirectives( TNode t ) {
    int tLineNum = t.getLocalLineNum();
    String tSource = (String) t.getAttribute("source");

    if ( tSource == null ) tSource = currentSource;
    if ( tLineNum == 0 ) tLineNum = lineNum;

    Vector preprocs = preprocessorInfoChannel.extractLinesPrecedingTokenNumber((Integer)t.getAttribute("tokenNumber"));
    printPreprocs(preprocs);
    
    if ( (lineNum != tLineNum) || !currentSource.equals(tSource) ) {  
        // we know we'll be newlines or a line directive or it probably
        // is just the case that this token is on the next line
        // either way start a new line and indent it
        currentOutput.println();
        lineNum++;      
        printTabs();
    }

    if ( ( lineNum == tLineNum ) && ( currentSource.equals(tSource) ) ){
        // do nothing special, we're at the right place
    }
    else if ( currentSource.equals(tSource) ) {  
        int diff = tLineNum - lineNum;
        if (diff > 0 && diff < lineDirectiveThreshold) {
            // print out the blank lines to bring us up to right line number
            for ( ; lineNum < tLineNum ; lineNum++ ) {
                currentOutput.println();
            }
        }
        else { // print line directive to get us to right line number
            // preserve flags 3 and 4 if present in current file
            if ( ! sourceFiles.empty() ) {
                LineObject l = (LineObject) sourceFiles.peek();
                StringBuffer tFlags = new StringBuffer("");
                if (l.getSystemHeader()) {
                    tFlags.append(" 3");
                }
                if (l.getTreatAsC()) {
                    tFlags.append(" 4");
                }
                currentOutput.println("# " + tLineNum + " \"" + tSource + "\"" + tFlags.toString());
                lineNum = tLineNum; 
            }
        }

        printTabs();
    }
    else { // different source
        Enumeration sources = sourceFiles.elements();
        // see if we're returning to a file we entered earlier
        boolean returningToEarlierFile = false;
        while (sources.hasMoreElements()) {
            LineObject l = (LineObject) sources.nextElement();
            if (l.getSource().equals(tSource)) {
                returningToEarlierFile = true;
                break;
            }
        }       
        if (returningToEarlierFile) {
            // pop off the files we're exiting, but never pop the trueSourceFile
            LineObject l = (LineObject) sourceFiles.peek();
            while ( ( l != trueSourceFile ) &&(! l.getSource().equals(tSource) ) ) {
                sourceFiles.pop();
                l = (LineObject) sourceFiles.peek();
            }
            
            // put in the return flag, plus others as needed
            StringBuffer tFlags = new StringBuffer(" 2");
            if (l.getSystemHeader()) {
                tFlags.append(" 3");
            }
            if (l.getTreatAsC()) {
                tFlags.append(" 4");
            }

            currentOutput.println("# " + tLineNum + " \"" + tSource + "\"" + tFlags);
            lineNum = tLineNum;
            currentSource = tSource;
            printTabs();
        }
        else {  // entering a file that wasn't in the original source
                // pretend we're entering it from top of stack
            currentOutput.println("# " + tLineNum + " \"" + tSource + "\"" + " 1");
            lineNum = tLineNum;
            currentSource = tSource;
            printTabs();
        }
    }
    currentOutput.print( t.getText() + " " );
}

/** It is not ok to print newlines from the String passed in as 
it will screw up the line number handling **/
void print( String s ) {
    currentOutput.print( s + " " );
}

void printTabs() {
    for ( int i = 0; i< tabs; i++ ) {
        currentOutput.print( "\t" );
    }
}
    
void commaSep( TNode t ) {
    print( t );
    if ( t.getNextSibling() != null ) {
        print( "," );
    }
}
    
        int traceDepth = 0;
        public void reportError(RecognitionException ex) {
          if ( ex != null)   {
           System.err.println("ANTLR Tree Parsing RecognitionException Error: " + ex.getClass().getName() + " " + ex );
                ex.printStackTrace(System.err);
          }
        }
        public void reportError(NoViableAltException ex) {
                System.err.println("ANTLR Tree Parsing NoViableAltException Error: " + ex.toString());
                TNode.printTree( ex.node );
                ex.printStackTrace(System.err);
        }
        public void reportError(MismatchedTokenException ex) {
          if ( ex != null)   {
                TNode.printTree( ex.node );
                System.err.println("ANTLR Tree Parsing MismatchedTokenException Error: " + ex );
                ex.printStackTrace(System.err);
          }
        }
        public void reportError(String s) {
                System.err.println("ANTLR Error from String: " + s);
        }
        public void reportWarning(String s) {
                System.err.println("ANTLR Warning from String: " + s);
        }
        protected void match(AST t, int ttype) throws MismatchedTokenException {
                //System.out.println("match("+ttype+"); cursor is "+t);
                super.match(t, ttype);
        }
        public void match(AST t, BitSet b) throws MismatchedTokenException {
                //System.out.println("match("+b+"); cursor is "+t);
                super.match(t, b);
        }
        protected void matchNot(AST t, int ttype) throws MismatchedTokenException {
                //System.out.println("matchNot("+ttype+"); cursor is "+t);
                super.matchNot(t, ttype);
                }
        public void traceIn(String rname, AST t) {
          traceDepth += 1;
          for (int x=0; x<traceDepth; x++) System.out.print(" ");
          super.traceIn(rname, t);   
        }
        public void traceOut(String rname, AST t) {
          for (int x=0; x<traceDepth; x++) System.out.print(" ");
          super.traceOut(rname, t);
          traceDepth -= 1;
        }



}
translationUnit 
options {
	defaultErrorHandler=false;
}
:{ initializePrinting(); }
               ( externalList )? 
                                { finalizePrinting(); }
        ;

externalList :( externalDef )+
        ;

externalDef :declaration
        |       functionDef
        |       asm_expr
	|	p:PREPROC_DIRECTIVE 		{print(p); }
        |       typelessDeclaration
        |       s:SEMI                          { print( s ); }
        ;

typelessDeclaration :#(NTypeMissing initDeclList s: SEMI)    { print( s ); }
        ;

asm_expr :#( a:"asm"                              { print( a ); } 
                 ( v:"volatile"                         { print( v ); } 
                 )? 
                    lc:LCURLY                           { print( lc ); tabs++; }
                    expr
                    rc:RCURLY                           { tabs--; print( rc ); }
                    s:SEMI                              { print( s ); }
                )
        ;

declaration :#( NDeclaration
                    declSpecifiers
                    (                   
                        initDeclList
                    )?
                    ( s:SEMI { print( s ); } )+
                )
        ;

declSpecifiers :(  storageClassSpecifier
                | typeQualifier
                | typeSpecifier
                )+
        ;

storageClassSpecifier :a:"auto"                                { print( a ); }
        |       b:"register"                    { print( b ); }
        |       c:"typedef"                     { print( c ); }
        |       functionStorageClassSpecifier
        ;

functionStorageClassSpecifier :a:"extern"                      { print( a ); }
        |       b:"static"                      { print( b ); }
        |       c:"inline"                      { print( c ); }
	|	d:"__inline"			{ print( d ); }
        ;

typeQualifier :a:"const"                       { print( a ); }
        |       b:"volatile"                    { print( b ); }
        ;

typeSpecifier :a:"void"                        { print( a ); }
        |       b:"char"                        { print( b ); }
        |       c:"short"                       { print( c ); }
        |       d:"int"                         { print( d ); }
        |       e:"long"                        { print( e ); }
        |       f:"float"                       { print( f ); }
        |       g:"double"                      { print( g ); }
        |       h:"signed"                      { print( h ); }
        |       j:"__builtin_va_list"           { print( j ); }
        |       i:"unsigned"                    { print( i ); }
        |       structSpecifier ( attributeDecl )*
        |       unionSpecifier  ( attributeDecl )*
        |       enumSpecifier
        |       typedefName
        |       #(n:"typeof" lp:LPAREN             { print( n ); print( lp ); }
                    ( (typeName )=> typeName 
                    | expr
                    )
                    rp:RPAREN                      { print( rp ); }
                )
        |       p:"__complex"                   { print( p ); }
        ;

typedefName :#(NTypedefName i:ID         { print( i ); } )
        ;

structSpecifier :#( a:"struct"                       { print( a ); }
                structOrUnionBody
            )
        ;

unionSpecifier :#( a:"union"                        { print( a ); }
                structOrUnionBody
            )
        ;

structOrUnionBody :( (ID LCURLY) => i1:ID lc1:LCURLY   { print( i1 ); print ( "{" ); tabs++; }

			( structDeclarationList )?

                  rc1:RCURLY             { tabs--; print( rc1 ); }
			(p2:PREPROC_DIRECTIVE		{ print( p2 ); })*
                |   lc2:LCURLY                      { print( "{" ); tabs++; }
			
                    ( structDeclarationList )?
			
                    rc2:RCURLY                      { tabs--; print( rc2 ); }
			(p5:PREPROC_DIRECTIVE		{ print( p5); })*
                | i2:ID                     { print( i2 ); }
                )
        ;

structDeclarationList :(p2:PREPROC_DIRECTIVE		{ print( p2 ); })*
		( 
			structDeclaration             { print( ";" ); }
			(p1:PREPROC_DIRECTIVE		{ print( p1); })*
                )+
        ;

structDeclaration :specifierQualifierList structDeclaratorList
        ;

specifierQualifierList :(
                typeSpecifier
                | typeQualifier
                )+
        ;

structDeclaratorList :structDeclarator
                ( { print(","); } structDeclarator )*
        ;

structDeclarator :#( NStructDeclarator       
            ( declarator )?
            ( c:COLON { print( c ); } expr )?
            ( attributeDecl )*
        )
        ;

enumSpecifier :#(  a:"enum"                        { print( a ); }
                ( i:ID { print( i ); } )? 
                ( lc:LCURLY                        { print( lc ); tabs++; }
			(p2:PREPROC_DIRECTIVE		{ print( p2 ); })*
                    enumList 
			 (p3:PREPROC_DIRECTIVE		{ print( p3 ); })*
                  rc:RCURLY                        { tabs--; print( rc ); }
                )?
                ( attributeDecl )*
           )

        ;

enumList :enumerator ( {print(",");} enumerator)*
        ;

enumerator :i:ID            { print( i ); }
                ( b:ASSIGN      { print( b ); }
                  expr
                )?
        ;

attributeDecl :#( a:"__attribute"            { print( a ); }
           (b:. { print( b ); } )*
        )
        | #( n:NAsmAttribute            { print( n ); }
             lp:LPAREN                  { print( lp ); }
             expr                       { print( ")" ); }
             rp:RPAREN                  { print( rp ); }
           )    
        ;

initDeclList :initDecl     
		( { print( "," ); } initDecl )*
        ;

initDecl { String declName = ""; }
:#(NInitDecl
                declarator
                ( attributeDecl )*
                ( a:ASSIGN              { print( a ); }
                  initializer
                | b:COLON               { print( b ); }
                  expr
                )?
                )
        ;

pointerGroup :#( NPointerGroup 
                   ( a:STAR             { print( a ); }
                    ( typeQualifier )* 
                   )+ 
                )
        ;

idList :i:ID                            { print( i ); }
                (  c:COMMA                      { print( c ); }
                   id:ID                        { print( id ); }
                )*
        ;

initializer :#( NInitializer (initializerElementLabel)? expr )
                | lcurlyInitializer
        ;

initializerElementLabel :#( NInitializerElementLabel
                (
                    ( l:LBRACKET              { print( l ); }
                        expr
                        r:RBRACKET            { print( r ); }
                        (a1:ASSIGN             { print( a1 ); } )?
                    )
                    | i1:ID c:COLON           { print( i1 ); print( c ); } 
                    | d:DOT i2:ID a2:ASSIGN      { print( d ); print( i2 ); print( a2 ); }
                )
            )
        ;

lcurlyInitializer :#(n:NLcurlyInitializer    { print( n ); tabs++; }
                initializerList       
                rc:RCURLY               { tabs--; print( rc ); } 
                )
        ;

initializerList :( i:initializer { commaSep( i ); }
                )*
        ;

declarator :#( NDeclarator
                ( pointerGroup )?               
                 ( re:"__restrict" { print(re); } )?
                 ( attributeDecl )*
                ( id:ID                         { print( id ); a = id.getText();}
                | lp:LPAREN { print( lp ); } declarator rp:RPAREN { print( rp ); }
                )?
                (   #( n:NParameterTypeList       {print( n ); func_name = a; 
			if(func_name.compareTo("SimSchedulerBasicP$TaskBasic$runTask")==0)
			{func_name="SchedulerBasicP$TaskBasic$runTask";}  }
                    (
                       parameterTypeList  
                        | (idList)?
                    )
                    r:RPAREN                      { print( r );}
		(p:PREPROC_DIRECTIVE		{ print( p );check=true; lineDir = p.getText();        									check_func=true;parseLine(3);})*
                    )
                 | lb:LBRACKET { print( lb );} (p2:PREPROC_DIRECTIVE { print( p2 );lineDir = p2.getText(); 											check=true;parseLine(1); })*
			( expr )?      (p1:PREPROC_DIRECTIVE { print( p1 );check=true; lineDir = p1.getText(); 													parseLine(1); })*
			rb:RBRACKET { print( rb ); }
                )*
             )
        ;

parameterTypeList :((p2:PREPROC_DIRECTIVE	{ print( p2 );check=true; lineDir = p2.getText(); parseLine(1); })*     			parameterDeclaration 
			
                    ( c:COMMA { print( c ); }
                      | s:SEMI { print( s ); }
                    )?
                )+
                ( v:VARARGS { print( v ); } )?
        ;

parameterDeclaration :#( NParameterDeclaration
                declSpecifiers
                (declarator | nonemptyAbstractDeclarator)?
                )
        ;

functionDef :#( NFunctionDef 
                ( functionDeclSpecifiers)?  
		 (p:PREPROC_DIRECTIVE 		{print(p);check=true; lineDir = p.getText(); parseLine(1); })*
                declarator
                ( declaration
                 | v:VARARGS    { print( v ); }
                )*
		
             	{isFunction = true;}
		compoundStatement 
		{returnAlert = false;}
            )
        ;

functionDeclSpecifiers :( functionStorageClassSpecifier
                | typeQualifier
                | typeSpecifier
                )+
        ;

declarationList :(   //ANTLR doesn't know that declarationList properly eats all the declarations
                    //so it warns about the ambiguity
                    options {
                        warnWhenFollowAmbig = false;
                    } :
                localLabelDecl 
                |  declaration	(p:PREPROC_DIRECTIVE { print( p );check=true; lineDir = p.getText(); parseLine(1);})*
                )+
        ;

localLabelDecl :#(a:"__label__"             { print( a ); }
              ( i:ID                    { commaSep( i ); }
              )+
                                        { print( ";" ); }
            )
        ;

compoundStatement :#( cs:NCompoundStatement                { print( cs );  adjustWhile(compoundStatement_AST_in);tabs++;
							if(isFunction){
								isFunction=false;
								adjustReturn(compoundStatement_AST_in);}
							}
		(p:PREPROC_DIRECTIVE		{ print( p );check=true;lineDir = p.getText(); parseLine(1);})*
                ( declarationList
                | functionDef
                )*
                ( statementList )?
                rc:RCURLY                               { tabs--; print( rc ); }
                )                               
                                                
        ;

statementList :{
		
		if(check_func){
			check_func=false;
			preTransform();
	    	}
		if(loopInsideFlag){
			loopInsideFlag = false;
			if(loop2Flag){
				loop2Flag=false;
				System.out.println("");
				//System.out.println ("printf(\"" + p2 + ":" + l2 + "\\n\");" + "//LoopingMagic");
				System.out.println("//LoopingMagic");
				System.out.print("check_time(" + printString2 + ");");
				printString2 = "";
				
				
	    		}
		}
		if(check){
			check=false;
			for(int i=0;i<dirCnt;i++){
				path=paths[i];
				line=lines[i];
				transform();
				paths[i]="";
				lines[i]="";
				
			}
			dirCnt=0;
	    	}
	    
	    }
			
	    ( statement )+
        ;

statement :statementBody 
        ;

statementBody :s:SEMI                          { print( s ); }

        |       compoundStatement       // Group of statements
	|	p:PREPROC_DIRECTIVE		{ print( p ); lineDir = p.getText(); parseLine(2); }
        |       #(NStatementExpr
                expr                    { print( ";" ); }
                )                    // Expressions

// Iteration statements:

        |       #( w:"while" { print( w ); print( "(" ); } 
                expr { print( ")" ); } 
		
                statement )

        |       #( d:"do" { print( d ); } 
		
                statement 
		(pl:PREPROC_DIRECTIVE 		{print(pl);System.out.println();})*
                        { print( " while ( " ); }
                expr 
                        { print( " );" ); }
                )

        |       #( f:"for" { print( f ); print( "(" ); }
                expr    { print( ";" ); }
                expr    { print( ";" ); }
                expr    { print( ")" ); }
		{loopInsideFlag = true;printString2=printString;printString = "";
		if(loopFlag){loopFlag=false;loop2Flag=true;}

		}
                statement
                )


// Jump statements:

        |       #( g:"goto"             { print( g );}  
                   expr                 { print( ";" ); } 
                )
        |       c:"continue"            { print( c ); print( ";" );}
        |       b:"break"               { print( b ); print( ";" );}
        |       #( r:"return"           { 	if(returnAlert){
							String temp1 = previousLine;
							String temp2 = previousPath;
							lineDir = forReturn; parseLine(2);
							previousLine=temp1;
							previousPath = temp2;
						}
					print( r ); }
                ( expr )? 
                                        { print( ";" ); }
                )


// Labeled statements:
        |       #( NLabel 
                ni:ID                   { print( ni ); print( ":" ); }
                ( statement )?
                )

        |       #( 
                ca:"case"               { print( ca ); }
                expr                    { print( ":" ); }
                (statement)? 
                )

        |       #( 
                de:"default"            { print( de ); print( ":" ); }
                (statement)? 
                )



// Selection statements:

        |       #( i:"if"               { print( i ); print( "(" ); }
                  expr                   { print( ")" ); }
		(pp:PREPROC_DIRECTIVE		{ print( pp ); lineDir = pp.getText(); parseLine(1); })*
                statement  
                (   
			e:"else"            { print( e ); }
		    (pc:PREPROC_DIRECTIVE		{ print( pc ); lineDir = pc.getText(); parseLine(1); })*
                    statement 
                )?
                )
        |       #( sw:"switch"          { print( sw ); print( "(" ); }
                expr                    { print( ")" ); }
                statement 
                )



        ;

expr :binaryExpr
        |       conditionalExpr
        |       castExpr
        |       unaryExpr
        |       postfixExpr
        |       primaryExpr
        |       emptyExpr
        |       compoundStatementExpr
        |       initializer
        |       rangeExpr
        |       gnuAsmExpr

	
	
		
        ;

emptyExpr :NEmptyExpression
        ;

compoundStatementExpr :#(l:LPAREN                  { print( l ); }
                compoundStatement 
                r:RPAREN                { print( r ); }
            )
        ;

rangeExpr :#(NRangeExpr expr v:VARARGS{ print( v ); } expr)
        ;

gnuAsmExpr :#(n:NGnuAsmExpr                        { print( n ); }
                (v:"volatile" { print( v ); } )? 
                lp:LPAREN               { print( lp ); }
                stringConst
                (  options { warnWhenFollowAmbig = false; }:
                    c1:COLON { print( c1 );} 
                    (strOptExprPair 
                        ( c2:COMMA { print( c2 ); } strOptExprPair)* 
                    )?
                  (  options { warnWhenFollowAmbig = false; }:
                    c3:COLON            { print( c3 ); }
                      (strOptExprPair 
                        ( c4:COMMA { print( c4 ); } strOptExprPair)* 
                      )?
                  )?
                )?
                ( c5:COLON              { print( c5 ); }
                  stringConst 
                  ( c6:COMMA            { print( c6 ); }
                    stringConst
                  )* 
                )?
                rp:RPAREN               { print( rp ); }
            )
        ;

strOptExprPair :stringConst 
            ( 
            l:LPAREN                    { print( l ); }
            expr 
            r:RPAREN                    { print( r ); }
            )?
        ;

binaryOperator :ASSIGN
        |       DIV_ASSIGN
        |       PLUS_ASSIGN
        |       MINUS_ASSIGN
        |       STAR_ASSIGN
        |       MOD_ASSIGN
        |       RSHIFT_ASSIGN
        |       LSHIFT_ASSIGN
        |       BAND_ASSIGN
        |       BOR_ASSIGN
        |       BXOR_ASSIGN
        |       LOR
        |       LAND
        |       BOR
        |       BXOR
        |       BAND
        |       EQUAL
        |       NOT_EQUAL
        |       LT
        |       LTE
        |       GT
        |       GTE
        |       LSHIFT
        |       RSHIFT
        |       PLUS
        |       MINUS
        |       STAR
        |       DIV
        |       MOD
        |       NCommaExpr
        ;

binaryExpr :b:binaryOperator
                    // no rules allowed as roots, so here I manually get 
                    // the first and second children of the binary operator
                    // and then print them out in the right order
                                        {       TNode e1, e2;
                                                e1 = (TNode) b.getFirstChild();
                                                e2 = (TNode) e1.getNextSibling();
                                                expr( e1 );
                                                print( b );
                                                expr( e2 );
                                        }
                                                
        ;

conditionalExpr :#( q:QUESTION 
                expr                    { print( q ); }
                ( expr )? 
                c:COLON                 { print( c ); }
                expr 
                )
        ;

castExpr :#( 
                c:NCast                 { print( c ); }
		
                typeName     
		        
                rp:RPAREN               { print( rp ); }
                expr   
                )
        ;

typeName :specifierQualifierList (nonemptyAbstractDeclarator)?
        ;

nonemptyAbstractDeclarator :#( NNonemptyAbstractDeclarator
            (   pointerGroup
                (   (lp1:LPAREN                         { print( lp1 ); }
                    (   nonemptyAbstractDeclarator
                        | parameterTypeList
                    )?
                    rp1:RPAREN                          { print( rp1 ); }
                    )
                | (
                    lb1:LBRACKET                        { print( lb1 ); }
                    (expr)? 
                    rb1:RBRACKET                        { print( rb1 ); }
                  )
                )*

            |  (   (lp2:LPAREN                          { print( lp2 ); }
                    (   nonemptyAbstractDeclarator
                        | parameterTypeList
                    )?
                    rp2:RPAREN                          { print( rp2 ); }
                   )
                | (
                    lb2:LBRACKET                        { print( lb2 ); }
                    (expr)? 
                    rb2:RBRACKET                        { print( rb2 ); }
                  )
                )+
            )
            )
        ;

unaryExpr :#( i:INC { print( i ); } expr )
        |       #( d:DEC { print( d ); } expr )
        |       #( NUnaryExpr u:unaryOperator { print( u ); } expr)
        |       #( s:"sizeof"                           { print( s ); }
                    ( ( LPAREN typeName )=> 
                        lps:LPAREN                      { print( lps ); }
                        typeName 
                        rps:RPAREN                      { print( rps ); }
                    | expr
                    )
                )
        |       #( a:"__alignof"                             { print( a ); }
                    ( ( LPAREN typeName )=> 
                        lpa:LPAREN                      { print( lpa ); }
                        typeName 
                        rpa:RPAREN                      { print( rpa ); }
                    | expr
                    )
                )
        ;

unaryOperator :BAND
        |       STAR
        |       PLUS
        |       MINUS
        |       BNOT
        |       LNOT
        |       LAND
        |       "__real"
        |       "__imag"
	|	PREPROC_DIRECTIVE
        ;

postfixExpr :#( NPostfixExpr
                    primaryExpr
                    ( a:PTR b:ID                                { print( a ); print( b ); }
                    | c:DOT d:ID                                { print( c ); print( d ); }
                    | #( n:NFunctionCallArgs                          { print( n ); }
                        (argExprList)?
                        rp:RPAREN                                     { print( rp ); }
                        )
                    | lb:LBRACKET                               { print( lb ); }
                        expr 
                        rb:RBRACKET                             { print( rb ); }
                    | f:INC                                     { print( f ); }
                    | g:DEC                                     { print( g ); }
                    )+
                )
        ;

primaryExpr :i:ID                            { print( i ); }
        |       n:Number                        { print( n ); }
        |       charConst
        |       stringConst

// JTC:
// ID should catch the enumerator
// leaving it in gives ambiguous err
//      | enumerator

        |       #( eg:NExpressionGroup          { print( eg ); }
                 expr                           { print( ")" ); }
                )
        ;

argExprList :expr ({print( "," );} expr )*
        ;

protected charConst :c:CharLiteral                   { print( c ); }
        ;

protected stringConst :#( NStringSeq
                    (
                    s:StringLiteral                 { print( s ); }
                    )+
                )
        ;

protected intConst :IntOctalConst
        |       LongOctalConst
        |       UnsignedOctalConst
        |       IntIntConst
        |       LongIntConst
        |       UnsignedIntConst
        |       IntHexConst
        |       LongHexConst
        |       UnsignedHexConst
        ;

protected floatConst :FloatDoubleConst
        |       DoubleDoubleConst
        |       LongDoubleConst
        ;

// inherited from grammar GnuCTreeParser
commaExpr :#(NCommaExpr expr expr)
        ;

// inherited from grammar GnuCTreeParser
assignExpr :#( ASSIGN expr expr)
        |       #( DIV_ASSIGN expr expr)
        |       #( PLUS_ASSIGN expr expr)
        |       #( MINUS_ASSIGN expr expr)
        |       #( STAR_ASSIGN expr expr)
        |       #( MOD_ASSIGN expr expr)
        |       #( RSHIFT_ASSIGN expr expr)
        |       #( LSHIFT_ASSIGN expr expr)
        |       #( BAND_ASSIGN expr expr)
        |       #( BOR_ASSIGN expr expr)
        |       #( BXOR_ASSIGN expr expr)
        ;

// inherited from grammar GnuCTreeParser
logicalOrExpr :#( LOR expr expr) 
        ;

// inherited from grammar GnuCTreeParser
logicalAndExpr :#( LAND expr expr )
        ;

// inherited from grammar GnuCTreeParser
inclusiveOrExpr :#( BOR expr expr )
        ;

// inherited from grammar GnuCTreeParser
exclusiveOrExpr :#( BXOR expr expr )
        ;

// inherited from grammar GnuCTreeParser
bitAndExpr :#( BAND expr expr )
        ;

// inherited from grammar GnuCTreeParser
equalityExpr :#( EQUAL expr expr)
        |       #( NOT_EQUAL expr expr)
        ;

// inherited from grammar GnuCTreeParser
relationalExpr :#( LT expr expr)
        |       #( LTE expr expr)
        |       #( GT expr expr)
        |       #( GTE expr expr)
        ;

// inherited from grammar GnuCTreeParser
shiftExpr :#( LSHIFT expr expr)
                | #( RSHIFT expr expr)
        ;

// inherited from grammar GnuCTreeParser
additiveExpr :#( PLUS expr expr)
        |       #( MINUS expr expr)
        ;

// inherited from grammar GnuCTreeParser
multExpr :#( STAR expr expr)
        |       #( DIV expr expr)
        |       #( MOD expr expr)
        ;


