-- |
-- Module      :  Language.LLVM.Parser.Monad
-- Copyright   :  (c) Harvard University 2006-2011
--                (c) Geoffrey Mainland 2011-2013
--                (c) Timo von Holtz 2014
-- License     :  BSD-style
-- Maintainer  :  tvh@tvholtz.de

{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module LLVM.Quote.Parser.Monad (
    P,
    runP,
    evalP,

    PState,
    emptyPState,

    getInput,
    setInput,
    pushLexState,
    popLexState,
    getLexState,
    getCurToken,
    setCurToken,

    useExts,
    antiquotationExts,

    LexerException(..),
    ParserException(..),
    quoteTok,
    failAt,
    lexerError,
    unexpectedEOF,
    emptyCharacterLiteral,
    illegalCharacterLiteral,
    illegalNumericalLiteral,
    parserError,
    unclosed,
    expected,
    expectedAt,

    AlexInput(..),
    alexGetChar,
    alexGetByte,
    alexInputPrevChar,
    nextChar,
    peekChar,
    maybePeekChar,
    skipChar,

    AlexPredicate,
    allowAnti,
    ifExtension
  ) where

import Control.Monad.Except
import Control.Exception (SomeException, Exception, toException)
import Control.Monad.State
import Data.Bits
import qualified Data.ByteString.Char8 as B
import Data.ByteString.Internal (c2w)
import Data.List (foldl')
import Data.Loc
import Data.Typeable (Typeable)
import Data.Word
import Text.PrettyPrint.Mainland
import Text.PrettyPrint.Mainland.Class

import LLVM.Quote.Parser.Tokens

data PState = PState
    { input      :: !AlexInput
    , curToken   :: L Token
    , lexState   :: ![Int]
    , extensions :: !ExtensionsInt
    }

emptyPState :: [Extensions]
            -> B.ByteString
            -> Pos
            -> PState
emptyPState exts buf pos = PState
    { input       = inp
    , curToken    = error "no token"
    , lexState    = [0]
    , extensions  = foldl' setBit 0 (map fromEnum exts)
    }
  where
    inp :: AlexInput
    inp = AlexInput
          { alexPos      = pos
          , alexPrevChar = '\n'
          , alexInput    = buf
          , alexOff      = 0
          }

newtype P a = P { runP :: PState -> Either SomeException (a, PState) }

instance Functor P where
    fmap = liftM

instance Applicative P where
    pure  = return
    (<*>) = ap

instance Monad P where
    m >>= k = P $ \s ->
        case runP m s of
          Left e         -> Left e
          Right (a, s')  -> runP (k a) s'

    m1 >> m2 = P $ \s ->
        case runP m1 s of
          Left e         -> Left e
          Right (_, s')  -> runP m2 s'

    return a = P $ \s -> Right (a, s)

    fail msg = do
        inp <- getInput
        throw $ ParserException (Loc (alexPos inp) (alexPos inp))
                                (ppr (alexPos inp) <> colon <+> text msg)

instance MonadState PState P where
    get    = P $ \s -> Right (s, s)
    put s  = P $ \_ -> Right ((), s)

instance MonadError SomeException P where
    throwError e = P $ \_ -> Left e
    m `catchError` h = P $ \s ->
        case runP m s of
          Left e -> runP (h e) s
          Right (a, s')  -> Right (a, s')

throw :: Exception e => e -> P a
throw e = P $ \_ -> Left (toException e)

evalP :: P a -> PState -> Either SomeException a
evalP comp st =
    case runP comp st of
      Left e        -> Left e
      Right (a, _)  -> Right a

getInput  :: P AlexInput
getInput = gets input

setInput  :: AlexInput -> P ()
setInput inp = modify $ \s ->
    s { input = inp }

pushLexState :: Int -> P ()
pushLexState ls = modify $ \s ->
    s { lexState = ls : lexState s }

popLexState :: P Int
popLexState = do
    ls <- getLexState
    modify $ \s ->
        s { lexState = tail (lexState s) }
    return ls

getLexState :: P Int
getLexState = gets (head . lexState)

getCurToken :: P (L Token)
getCurToken = gets curToken

setCurToken :: L Token -> P ()
setCurToken tok = modify $ \s -> s { curToken = tok }

antiquotationExts :: ExtensionsInt
antiquotationExts = (bit . fromEnum) Antiquotation

useExts :: ExtensionsInt -> P Bool
useExts ext = gets $ \s ->
    extensions s .&. ext /= 0

data LexerException = LexerException Pos Doc
  deriving (Typeable)

instance Exception LexerException where

instance Show LexerException where
    show (LexerException pos msg) =
        show $ prettyCompact $ nest 4 $ ppr pos <> text ":" </> msg

data ParserException = ParserException Loc Doc
  deriving (Typeable)

instance Exception ParserException where

instance Show ParserException where
    show (ParserException loc msg) =
        show $ prettyCompact $ nest 4 $ ppr loc <> text ":" </> msg

quoteTok :: Doc -> Doc
quoteTok = enclose (char '`') (char '\'')

failAt :: Loc -> String -> P a
failAt loc msg =
    throw $ ParserException loc (text msg)

lexerError :: AlexInput -> Doc -> P a
lexerError inp s =
    throw $ LexerException (alexPos inp) (text "lexer error on" <+> s)

unexpectedEOF :: AlexInput -> P a
unexpectedEOF inp =
    lexerError inp (text "unexpected end of file")

emptyCharacterLiteral :: AlexInput -> P a
emptyCharacterLiteral inp =
    lexerError inp (text "empty character literal")

illegalCharacterLiteral :: AlexInput -> P a
illegalCharacterLiteral inp =
    lexerError inp (text "illegal character literal")

illegalNumericalLiteral :: AlexInput -> P a
illegalNumericalLiteral inp =
    lexerError inp (text "illegal numerical literal")

parserError :: Loc -> Doc -> P a
parserError loc msg =
    throw $ ParserException loc msg

unclosed :: Loc -> String -> P a
unclosed loc x =
    parserError (locEnd loc) (text "unclosed" <+> quoteTok (text x))

expected :: [String] -> Maybe String -> P b
expected alts after = do
    tok <- getCurToken
    expectedAt tok alts after

expectedAt :: L Token -> [String] -> Maybe String -> P b
expectedAt tok@(L loc _) alts after =
    parserError
      (locStart loc)
      (text "expected" <+> pprAlts alts <+> pprGot tok <> pprAfter after)
  where
    pprAlts :: [String] -> Doc
    pprAlts []        = empty
    pprAlts [s]       = text s
    pprAlts [s1, s2]  = text s1 <+> text "or" <+> text s2
    pprAlts (s : ss)  = text s <> comma <+> pprAlts ss

    pprGot :: L Token -> Doc
    pprGot (L _ Teof)  = text "but reached end of file"
    pprGot (L _ t)     = text "but got" <+> quoteTok (ppr t)

    pprAfter :: Maybe String -> Doc
    pprAfter Nothing     = empty
    pprAfter (Just what) = text " after" <+> text what

data AlexInput = AlexInput
  {  alexPos      :: {-#UNPACK#-} !Pos
  ,  alexPrevChar :: {-#UNPACK#-} !Char
  ,  alexInput    :: {-#UNPACK#-} !B.ByteString
  ,  alexOff      :: {-#UNPACK#-} !Int
  }

alexGetChar :: AlexInput -> Maybe (Char, AlexInput)
alexGetChar inp =
  case B.uncons (alexInput inp) of
    Nothing      -> Nothing
    Just (c, bs) -> Just (c, inp  { alexPos      = advancePos (alexPos inp) c
                                  , alexPrevChar = c
                                  , alexInput    = bs
                                  , alexOff      = alexOff inp + 1
                                  })

alexGetByte :: AlexInput -> Maybe (Word8, AlexInput)
alexGetByte inp =
    case alexGetChar inp of
      Nothing        -> Nothing
      Just (c, inp') -> Just (c2w c, inp')

alexInputPrevChar :: AlexInput -> Char
alexInputPrevChar = alexPrevChar

nextChar :: P Char
nextChar = do
    inp <- getInput
    case alexGetChar inp of
      Nothing         -> unexpectedEOF inp
      Just (c, inp')  -> setInput inp' >> return c

peekChar ::P Char
peekChar = do
    inp <- getInput
    case B.uncons (alexInput inp) of
      Nothing      -> unexpectedEOF inp
      Just (c, _)  -> return c

maybePeekChar :: P (Maybe Char)
maybePeekChar = do
    inp <- getInput
    case alexGetChar inp of
      Nothing      -> return Nothing
      Just (c, _)  -> return (Just c)

skipChar :: P ()
skipChar = do
    inp <- getInput
    case alexGetChar inp of
      Nothing         -> unexpectedEOF inp
      Just (_, inp')  -> setInput inp'

-- | The components of an 'AlexPredicate' are the predicate state, input stream
-- before the token, length of the token, input stream after the token.
type AlexPredicate =  PState
                   -> AlexInput
                   -> Int
                   -> AlexInput
                   -> Bool

allowAnti :: AlexPredicate
allowAnti = ifExtension antiquotationExts

ifExtension :: ExtensionsInt -> AlexPredicate
ifExtension i s _ _ _ = extensions s .&. i /= 0
