-- Implicit CAD. Copyright (C) 2011, Christopher Olah (chris@colah.ca)
-- Released under the GNU GPL, see LICENSE

-- We'd like to parse openscad code, with some improvements, for backwards compatability.

-- This file provides primitive objects for the openscad parser.
-- The code is fairly straightforward; an explanation of how 
-- the first one works is provided.

{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies, FlexibleInstances, FlexibleContexts, TypeSynonymInstances, UndecidableInstances, ScopedTypeVariables  #-}

module Graphics.Implicit.ExtOpenScad.Primitives (primitives) where

import Graphics.Implicit.Definitions
import Graphics.Implicit.ExtOpenScad.Definitions
import Graphics.Implicit.ExtOpenScad.Util
import Graphics.Implicit.ExtOpenScad.Util.ArgParser
import Graphics.Implicit.ExtOpenScad.Util.Computation

import qualified Graphics.Implicit.Primitives as Prim
import Data.Maybe (fromMaybe, isNothing)
import qualified Graphics.Implicit.SaneOperators as S

primitives :: [(String, [ComputationStateModifier] ->  ArgParser ComputationStateModifier)]
primitives = [ sphere, cube, square, cylinder, circle, polygon, union, difference, intersect, translate, scale, rotate, extrude, pack, shell, rotateExtrude ]

moduleWithSuite name modArgMapper = (name, modArgMapper)
moduleWithoutSuite name modArgMapper = (name, \suite -> modArgMapper)


-- **Exmaple of implementing a module**
-- sphere is a module without a suite named sphere,
-- this means that the parser will look for this like
--       sphere(args...);
sphere = moduleWithoutSuite "sphere" $ do
	example "sphere(3);"
	example "sphere(r=5);"
	-- What are the arguments?
	-- The radius, r, which is a (real) number.
	-- Because we don't provide a default, this ends right
	-- here if it doesn't get a suitable argument!
	r :: ℝ <- argument "r" 
	            `doc` "radius of the sphere"
	-- So what does this module do?
	-- It adds a 3D object, a sphere of radius r,
	-- using the sphere implementation in Prim
	-- (Graphics.Implicit.Primitives)
	addObj3 $ Prim.sphere r

cube = moduleWithoutSuite "cube" $ do

	-- examples
	example "cube(size = [2,3,4], center = true, r = 0.5);"
	example "cube(4);"

	-- arguments
	size   :: Either ℝ ℝ3  <- argument "size"
	                    `doc` "cube size"
	center :: Bool <- argument "center" 
	                    `doc` "should center?"  
	                    `defaultTo` False
	r      :: ℝ    <- argument "r"
	                    `doc` "radius of rounding" 
	                    `defaultTo` 0

	-- Tests
	test "cube(4);"
		`eulerCharacteristic` 2
	test "cube(size=[2,3,4]);"
		`eulerCharacteristic` 2

	-- A helper function for making rect3's accounting for centerdness
	let rect3 x y z = 
		if center  
		then Prim.rect3R r (-x/2, -y/2, -z/2) (x/2, y/2, z/2)
		else Prim.rect3R r (0, 0, 0)  (x, y, z)

	case size of
		Right (x,y,z) -> addObj3 $ rect3 x y z
		Left   w      -> addObj3 $ rect3 w w w



square = moduleWithoutSuite "square" $ do

	-- examples 
	example "square(size = [3,4], center = true, r = 0.5);"
	example "square(4);"

	-- arguments
	size   :: Either ℝ ℝ2  <- argument "size"
	                    `doc`  "square size"
	center :: Bool <- argument "center" 
	                    `doc` "should center?"  
	                    `defaultTo` False
	r      :: ℝ    <- argument "r"
	                    `doc` "radius of rounding" 
	                    `defaultTo` 0

	-- Tests
	test "square(2);"
		`eulerCharacteristic` 0
	test "square(size=[2,3]);"
		`eulerCharacteristic` 0

	-- A helper function for making rect2's accounting for centerdness
	let rect x y = 
		if center  
		then Prim.rectR r (-x/2, -y/2) (x/2, y/2)
		else Prim.rectR r (  0,    0 ) ( x,   y )

	-- caseOType matches depending on whether size can be coerced into
	-- the right object. See Graphics.Implicit.ExtOpenScad.Util
	case size of
		Left   w    -> addObj2 $ rect w w
		Right (x,y) -> addObj2 $ rect x y



cylinder = moduleWithoutSuite "cylinder" $ do

	example "cylinder(r=10, h=30, center=true);"
	example "cylinder(r1=4, r2=6, h=10);"
	example	"cylinder(r=5, h=10, $fn = 6);"

	-- arguments
	r      :: ℝ    <- argument "r"
				`defaultTo` 1
				`doc` "radius of cylinder"
	h      :: ℝ    <- argument "h"
				`defaultTo` 1
				`doc` "height of cylinder"
	r1     :: ℝ    <- argument "r1"
				`defaultTo` 1
				`doc` "bottom radius; overrides r"
	r2     :: ℝ    <- argument "r2"
				`defaultTo` 1
				`doc` "top radius; overrides r"
	fn     :: ℕ    <- argument "$fn"
				`defaultTo` (-1)
				`doc` "number of sides, for making prisms"
	center :: Bool <- argument "center"
				`defaultTo` False
				`doc` "center cylinder with respect to z?"

	-- Tests
	test "cylinder(r=10, h=30, center=true);"
		`eulerCharacteristic` 0
	test "cylinder(r=5, h=10, $fn = 6);"
		`eulerCharacteristic` 0

	-- The result is a computation state modifier that adds a 3D object, 
	-- based on the args.
	addObj3 $ if r1 == 1 && r2 == 1
		then let
			obj2 = if fn  < 0 then Prim.circle r else Prim.polygonR 0 $
				let sides = fromIntegral fn 
				in [(r*cos θ, r*sin θ )| θ <- [2*pi*n/sides | n <- [0.0 .. sides - 1.0]]]
			obj3 = Prim.extrudeR 0 obj2 h
		in if center
			then Prim.translate (0,0,-h/2) obj3
			else obj3
		else if center
			then  Prim.translate (0,0,-h/2) $ Prim.cylinder2 r1 r2 h
			else Prim.cylinder2  r1 r2 h

circle = moduleWithoutSuite "circle" $ do
	
	example "circle(r=10); // circle"
	example "circle(r=5, $fn=6); //hexagon"

	-- Arguments
	r  :: ℝ <- argument "r"
		`doc` "radius of the circle"
	fn :: ℕ <- argument "$fn" 
		`doc` "if defined, makes a regular polygon with n sides instead of a circle"
		`defaultTo` (-1)

	test "circle(r=10);"
		`eulerCharacteristic` 0

	if fn < 3
		then addObj2 $ Prim.circle r
		else addObj2 $ Prim.polygonR 0 $
			let sides = fromIntegral fn 
			in [(r*cos θ, r*sin θ )| θ <- [2*pi*n/sides | n <- [0.0 .. sides - 1.0]]]

polygon = moduleWithoutSuite "polygon" $ do
	
	example "polygon ([(0,0), (0,10), (10,0)]);"
	
	points :: [ℝ2] <-  argument "points" 
	                    `doc` "vertices of the polygon"
	paths :: [ℕ ]  <- argument "paths" 
	                    `doc` "order to go through vertices; ignored for now"
	                    `defaultTo` []
	r      :: ℝ     <- argument "r"
	                    `doc` "rounding of the polygon corners; ignored for now"
	                    `defaultTo` 0
	case paths of
		[] -> addObj2 $ Prim.polygonR 0 points
		_ -> noChange;




union = moduleWithSuite "union" $ \suite -> do
	r :: ℝ <- argument "r"
		`defaultTo` 0.0
		`doc` "Radius of rounding for the union interface"
	if r > 0
		then getAndCompressSuiteObjs suite (Prim.unionR r) (Prim.unionR r)
		else getAndCompressSuiteObjs suite Prim.union Prim.union

intersect = moduleWithSuite "intersection" $ \suite -> do
	r :: ℝ <- argument "r"
		`defaultTo` 0.0
		`doc` "Radius of rounding for the intersection interface"
	if r > 0
		then getAndCompressSuiteObjs suite (Prim.intersectR r) (Prim.intersectR r)
		else getAndCompressSuiteObjs suite Prim.intersect Prim.intersect

difference = moduleWithSuite "difference" $ \suite -> do
	r :: ℝ <- argument "r"
		`defaultTo` 0.0
		`doc` "Radius of rounding for the difference interface"
	if r > 0
		then getAndCompressSuiteObjs suite (Prim.differenceR r) (Prim.differenceR r)
		else getAndCompressSuiteObjs suite Prim.difference Prim.difference

translate = moduleWithSuite "translate" $ \suite -> do

	example "translate ([2,3]) circle (4);"
	example "translate ([5,6,7]) sphere(5);"

	v :: Either ℝ (Either ℝ2 ℝ3) <- argument "v"
		`doc` "vector to translate by"
	
	let 
		translateObjs shift2 shift3 = 
			getAndTransformSuiteObjs suite (Prim.translate shift2) (Prim.translate shift3)
	
	case v of
		Left   x              -> translateObjs (x,0) (x,0,0)
		Right (Left (x,y))    -> translateObjs (x,y) (x,y,0.0)
		Right (Right (x,y,z)) -> translateObjs (x,y) (x,y,z)

deg2rad x = x / 180.0 * pi

-- This is mostly insane
rotate = moduleWithSuite "rotate" $ \suite -> do
	a <- argument "a"
		`doc` "value to rotate by; angle or list of angles"

	-- caseOType matches depending on whether size can be coerced into
	-- the right object. See Graphics.Implicit.ExtOpenScad.Util
	-- Entries must be joined with the operator <||>
	-- Final entry must be fall through.
	caseOType a $
		       ( \xy  ->
			getAndTransformSuiteObjs suite (Prim.rotate $ deg2rad xy ) (Prim.rotate3 (deg2rad xy, 0, 0) )
		) <||> ( \(yz,xy,xz) ->
			getAndTransformSuiteObjs suite (Prim.rotate $ deg2rad xy ) (Prim.rotate3 (deg2rad yz, deg2rad xz, deg2rad xy) )
		) <||> ( \(yz,xz) ->
			getAndTransformSuiteObjs suite (id ) (Prim.rotate3 (deg2rad yz, deg2rad xz, 0))
		) <||> ( \_  -> noChange )


scale = moduleWithSuite "scale" $ \suite -> do

	example "scale(2) square(5);"
	example "scale([2,3]) square(5);"
	example "scale([2,3,4]) cube(5);"

	v :: Either ℝ (Either ℝ2 ℝ3) <- argument "v"
		`doc` "vector or scalar to scale by"
	
	let
		scaleObjs strech2 strech3 = 
			getAndTransformSuiteObjs suite (Prim.scale strech2) (Prim.scale strech3)
	
	case v of
		Left   x              -> scaleObjs (x,0) (x,0,0)
		Right (Left (x,y))    -> scaleObjs (x,y) (x,y,0.0)
		Right (Right (x,y,z)) -> scaleObjs (x,y) (x,y,z)

extrude = moduleWithSuite "linear_extrude" $ \suite -> do
	example "linear_extrude(10) square(5);"

	height :: Either ℝ (ℝ -> ℝ -> ℝ) <- argument "height" `defaultTo` (Left 1)
		`doc` "height to extrude to..."
	center :: Bool <- argument "center" `defaultTo` False
		`doc` "center? (the z component)"
	twist  :: Maybe (Either ℝ (ℝ  -> ℝ)) <- argument "twist"  `defaultTo` Nothing
		`doc` "twist as we extrude, either a total amount to twist or a function..."
	scale  :: Maybe (Either ℝ (ℝ  -> ℝ)) <- argument "scale"  `defaultTo` Nothing
		`doc` "scale according to this funciton as we extrud..."
	translate :: Maybe (Either ℝ2 (ℝ -> ℝ2)) <- argument "translate"  `defaultTo` Nothing
		`doc` "translate according to this funciton as we extrude..."
	r      :: ℝ   <- argument "r"      `defaultTo` 0
		`doc` "round the top?"
	
	let
		degRotate = (\θ (x,y) -> (x*cos(θ)+y*sin(θ), y*cos(θ)-x*sin(θ))) . (*(2*pi/360))

		heightn = case height of
				Left  h -> h
				Right f -> f 0 0

		height' = case height of
			Right f -> Right $ uncurry f
			Left a -> Left a

		shiftAsNeeded =
			if center
			then Prim.translate (0,0,-heightn/2.0)
			else id
		
		funcify :: S.Multiplicative ℝ a a => Either a (ℝ -> a) -> ℝ -> a
		funcify (Left val) h = (h/heightn) S.* val
		funcify (Right f ) h = f h
		
		twist' = fmap funcify twist
		scale' = fmap funcify scale
		translate' = fmap funcify translate
	
	getAndModUpObj2s suite $ \obj -> case height of
		Left constHeight | isNothing twist && isNothing scale && isNothing translate ->
			shiftAsNeeded $ Prim.extrudeR r obj constHeight
		_ -> 
			shiftAsNeeded $ Prim.extrudeRM r twist' scale' translate' obj height'

rotateExtrude = moduleWithSuite "rotate_extrude" $ \suite -> do
	--example "extrude(10) square(5);"

	totalRot :: ℝ <- argument "a" `defaultTo` 360
		`doc` "angle to sweep"
	cap      :: Bool <- argument "cap" `defaultTo` False
	r        :: ℝ    <- argument "r"   `defaultTo` 0
	translate :: Either ℝ2 (ℝ -> ℝ2) <- argument "translate" `defaultTo` Left (0,0)

	let
		capM = if cap then Just r else Nothing
	
	getAndModUpObj2s suite $ \obj -> Prim.rotateExtrude totalRot capM translate obj



{-rotateExtrudeStatement = moduleWithSuite "rotate_extrude" $ \suite -> do
	h <- realArgument "h"
	center <- boolArgumentWithDefault "center" False
	twist <- realArgumentWithDefault 0.0
	r <- realArgumentWithDefault "r" 0.0
	getAndModUpObj2s suite (\obj -> Prim.extrudeRMod r (\θ (x,y) -> (x*cos(θ)+y*sin(θ), y*cos(θ)-x*sin(θ)) )  obj h) 
-}

shell = moduleWithSuite "shell" $ \suite -> do
	w :: ℝ <- argument "w"
			`doc` "width of the shell..."
	
	getAndTransformSuiteObjs suite (Prim.shell w) (Prim.shell w)

-- Not a perenant solution! Breaks if can't pack.
pack = moduleWithSuite "pack" $ \suite -> do

	example "pack ([45,45], sep=2) { circle(10); circle(10); circle(10); circle(10); }"

	-- arguments
	size :: ℝ2 <- argument "size"
		`doc` "size of 2D box to pack objects within"
	sep  :: ℝ  <- argument "sep"
		`doc` "mandetory space between objects"

	-- The actual work...
	return $  \ ioWrappedState -> do
		(varlookup,  obj2s,  obj3s)  <- ioWrappedState
		(varlookup2, obj2s2, obj3s2) <- runComputations (return (varlookup, [], [])) suite
		if not $ null obj3s2
			then case Prim.pack3 size sep obj3s2 of
				Just solution -> return (varlookup2, obj2s, obj3s ++ [solution] )
				Nothing       -> do 
					putStrLn "Can't pack given objects in given box with present algorithm"
					return (varlookup2, obj2s, obj3s)
			else case Prim.pack2 size sep obj2s2 of
				Just solution -> return (varlookup2, obj2s ++ [solution], obj3s)
				Nothing       -> do 
					putStrLn "Can't pack given objects in given box with present algorithm"
					return (varlookup2, obj2s, obj3s)

