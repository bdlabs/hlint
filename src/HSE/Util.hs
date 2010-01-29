{-# LANGUAGE FlexibleContexts #-}

module HSE.Util where

import Control.Monad
import Data.List
import HSE.Type


---------------------------------------------------------------------
-- ACCESSOR/TESTER

opExp :: QOp S -> Exp_
opExp (QVarOp s op) = Var s op
opExp (QConOp s op) = Con s op

moduleDecls :: Module_ -> [Decl_]
moduleDecls (Module _ _ _ _ xs) = xs

moduleName :: Module_ -> String
moduleName (Module _ Nothing _ _ _) = "Main"
moduleName (Module _ (Just (ModuleHead _ (ModuleName _ x) _ _)) _ _ _) = x

moduleImports :: Module_ -> [ImportDecl S]
moduleImports (Module _ _ _ x _) = x

modulePragmas :: Module_ -> [OptionPragma S]
modulePragmas (Module _ _ x _ _) = x

isChar :: Exp_ -> Bool
isChar (Lit _ Char{}) = True
isChar _ = False

fromChar :: Exp_ -> Char
fromChar (Lit _ (Char _ x _)) = x

isString :: Exp_ -> Bool
isString (Lit _ String{}) = True
isString _ = False

fromString :: Exp_ -> String
fromString (Lit _ (String _ x _)) = x

isPString (PLit _ String{}) = True; isPString _ = False
fromPString (PLit _ (String _ x _)) = x

fromParen :: Exp_ -> Exp_
fromParen (Paren _ x) = fromParen x
fromParen x = x

fromPParen :: Pat s -> Pat s
fromPParen (PParen _ x) = fromPParen x
fromPParen x = x

-- is* :: Exp -> Bool
isVar Var{} = True; isVar _ = False
isApp App{} = True; isApp _ = False
isInfixApp InfixApp{} = True; isInfixApp _ = False
isList List{} = True; isList _ = False
isAnyApp x = isApp x || isInfixApp x
isParen Paren{} = True; isParen _ = False
isLambda Lambda{} = True; isLambda _ = False
isMDo MDo{} = True; isMDo _ = False
isBoxed Boxed{} = True; isBoxed _ = False
isDerivDecl DerivDecl{} = True; isDerivDecl _ = False
isFunDep FunDep{} = True; isFunDep _ = False
isPBangPat PBangPat{} = True; isPBangPat _ = False
isPExplTypeArg PExplTypeArg{} = True; isPExplTypeArg _ = False
isPFieldPun PFieldPun{} = True; isPFieldPun _ = False
isPFieldWildcard PFieldWildcard{} = True; isPFieldWildcard _ = False
isPViewPat PViewPat{} = True; isPViewPat _ = False
isParComp ParComp{} = True; isParComp _ = False
isPatTypeSig PatTypeSig{} = True; isPatTypeSig _ = False
isQuasiQuote QuasiQuote{} = True; isQuasiQuote _ = False


-- which names are bound by a declaration
declBind :: Decl_ -> [String]
declBind (FunBind _ (Match _ x _ _ _ : _)) = [prettyPrint x]
declBind (PatBind _ x _ _ _) = pvars x
declBind _ = []


allowRightSection x = x `notElem` ["-","#"]
allowLeftSection x = x /= "#"

---------------------------------------------------------------------
-- HSE FUNCTIONS


getEquations :: Decl s -> [Decl s]
getEquations (FunBind s xs) = map (FunBind s . (:[])) xs
getEquations (PatBind s (PVar _ name) _ bod bind) = [FunBind s [Match s name [] bod bind]]
getEquations x = [x]


---------------------------------------------------------------------
-- VECTOR APPLICATION


apps :: [Exp_] -> Exp_
apps = foldl1 (App an)


fromApps :: Exp_ -> [Exp_]
fromApps (App _ x y) = fromApps x ++ [y]
fromApps x = [x]


-- Rule for the Uniplate Apps functions
-- Given (f a) b, consider the children to be: children f ++ [a,b]

childrenApps :: Exp_ -> [Exp_]
childrenApps (App _ x@App{} y) = childrenApps x ++ [y]
childrenApps (App _ x y) = children x ++ [y]
childrenApps x = children x


descendApps :: (Exp_ -> Exp_) -> Exp_ -> Exp_
descendApps f (App s x@App{} y) = App s (descendApps f x) (f y)
descendApps f (App s x y) = App s (descend f x) (f y)
descendApps f x = descend f x


descendAppsM :: Monad m => (Exp_ -> m Exp_) -> Exp_ -> m Exp_
descendAppsM f (App s x@App{} y) = liftM2 (App s) (descendAppsM f x) (f y)
descendAppsM f (App s x y) = liftM2 (App s) (descendM f x) (f y)
descendAppsM f x = descendM f x


universeApps :: Exp_ -> [Exp_]
universeApps x = x : concatMap universeApps (childrenApps x)

transformApps :: (Exp_ -> Exp_) -> Exp_ -> Exp_
transformApps f = f . descendApps (transformApps f)

transformAppsM :: (Monad m) => (Exp_ -> m Exp_) -> Exp_ -> m Exp_
transformAppsM f x = f =<< descendAppsM (transformAppsM f) x


---------------------------------------------------------------------
-- UNIPLATE FUNCTIONS

universeS :: Biplate x (f S) => x -> [f S]
universeS = universeBi

childrenS :: Biplate x (f S) => x -> [f S]
childrenS = childrenBi


vars :: Biplate a Exp_ => a -> [String]
vars xs = [prettyPrint x | Var _ (UnQual _ x) <- universeS xs]

pvars :: Biplate a Pat_ => a -> [String]
pvars xs = [prettyPrint x | PVar _ x <- universeS xs]


-- return the parent along with the child
universeParentExp :: Biplate a Exp_ => a -> [(Maybe (Int, Exp_), Exp_)]
universeParentExp xs = concat [(Nothing, x) : f x | x <- childrenBi xs]
    where f p = concat [(Just (i,p), c) : f c | (i,c) <- zip [0..] $ children p]


---------------------------------------------------------------------
-- SRCLOC FUNCTIONS

showSrcLoc :: SrcLoc -> String
showSrcLoc (SrcLoc file line col) = file ++ ":" ++ show line ++ ":" ++ show col ++ ":"

toSrcLoc :: SrcInfo si => si -> SrcLoc
toSrcLoc = getPointLoc

nullSrcLoc :: SrcLoc
nullSrcLoc = SrcLoc "" 0 0

an :: SrcSpanInfo
an = toSrcInfo nullSrcLoc [] nullSrcLoc

dropAnn :: Functor f => f s -> f ()
dropAnn = fmap (const ())


---------------------------------------------------------------------
-- SRCLOC EQUALITY

-- enforce all being on S, as otherwise easy to =~= on a Just, and get the wrong functor

x /=~= y = not $ x =~= y

elem_ :: (Annotated f, Eq (f ())) => f S -> [f S] -> Bool
elem_ x y = any (x =~=) y

nub_ :: (Annotated f, Eq (f ())) => [f S] -> [f S]
nub_ = nubBy (=~=)

intersect_ :: (Annotated f, Eq (f ())) => [f S] -> [f S] -> [f S]
intersect_ = intersectBy (=~=)

eqList, neqList :: (Annotated f, Eq (f ())) => [f S] -> [f S] -> Bool
neqList x y = not $ eqList x y
eqList (x:xs) (y:ys) = x =~= y && eqList xs ys
eqList [] [] = True
eqList _ _ = False

eqMaybe:: (Annotated f, Eq (f ())) => Maybe (f S) -> Maybe (f S) -> Bool
eqMaybe (Just x) (Just y) = x =~= y
eqMaybe Nothing Nothing = True
eqMaybe _ _ = False

