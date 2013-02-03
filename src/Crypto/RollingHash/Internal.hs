{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeFamilies #-}

module Crypto.RollingHash.Internal where

import Data.Word
import Foreign          hiding (unsafePerformIO)
import System.IO.Unsafe        (unsafePerformIO)

import qualified Data.ByteString               as BS
import qualified Data.ByteString.Internal      as BSI
import qualified Data.ByteString.Lazy          as BL
import qualified Data.ByteString.Lazy.Internal as BLI
import qualified Data.ByteString.Unsafe        as BU

{- stolen from Data.Random.Internal.Words

{-# INLINE buildWord32 #-}
buildWord32 :: Word8 -> Word8 -> Word8 -> Word8 -> Word32
buildWord32 b0 b1 b2 b3 = unsafePerformIO . allocaBytes 4 $ \p -> do
  pokeByteOff p 0 b0
  pokeByteOff p 1 b1
  pokeByteOff p 2 b2
  pokeByteOff p 3 b3
  peek (castPtr p)
-}

buildWord32' :: Word16 -> Word16 -> Word32
buildWord32' w0 w1 = unsafePerformIO . allocaBytes 4 $ \p -> do
  pokeByteOff p 0 w0
  pokeByteOff p 2 w1
  peek (castPtr p)
{-# INLINE buildWord32' #-}

data R a = R
  { dat_0 :: !a
  , dat_l :: !a                        -- ^ list 'dat_0' at offset l
  , var_l :: {-# UNPACK #-} !Word8
  , hsh_a :: {-# UNPACK #-} !Word16
  , hsh_b :: {-# UNPACK #-} !Word16
  }
  deriving Show

class Rolling a where
  emptyR   :: R a
  isEmptyR :: R a -> Bool
  splitR   :: a -> (Word8,a)  -- ^ should return @(0,empty)@ for empty input
  dropR    :: Word8 -> a -> a

instance Rolling [Word8] where
  emptyR = R [] [] 0 0 0
  {-# INLINE emptyR #-}

  isEmptyR r = null (dat_l r)
  {-# INLINE isEmptyR #-}

  splitR (x:r) = (x,r)
  splitR []    = (0,[])
  {-# INLINE splitR #-}

  dropR = drop . fromIntegral
  {-# INLINE dropR #-}

instance Rolling BL.ByteString where
  emptyR = R BL.empty BL.empty 0 0 0
  {-# INLINE emptyR #-}

  isEmptyR r = {-# SCC "isEmptyR" #-} BL.null (dat_l r)
  {-# INLINE isEmptyR #-}

  -- re-implement 'BL.uncons' without 'Maybe'
  splitR bs = {-# SCC "splitR" #-} case bs of
    BLI.Empty      -> {-# SCC "empty" #-} (0, BLI.Empty)
    BLI.Chunk c cs ->
      case c of
           BSI.PS _ _ 1 ->
             {-# SCC "last" #-}
             ( {-# SCC "head" #-} BU.unsafeHead c
             , {-# SCC "cs"   #-} cs)
           _ -> 
             {-# SCC "chunk" #-}
             ( BU.unsafeHead c
             , BLI.Chunk (BU.unsafeTail c) cs)
  {-# INLINE splitR #-}

  dropR = {-# SCC "dropR" #-} BL.drop . fromIntegral
  {-# INLINE dropR #-}

instance Rolling BS.ByteString where
  emptyR = R BS.empty BS.empty 0 0 0
  {-# INLINE emptyR #-}

  isEmptyR r = BS.null (dat_l r)
  {-# INLINE isEmptyR #-}

  -- re-implement 'BS.uncons' without 'Maybe'
  splitR bs@(BSI.PS x s l) =
    case l of
         0 -> (0, bs)
         _ -> (BU.unsafeHead bs, BSI.PS x (s+1) (l-1))
  {-# INLINE splitR #-}

  dropR = BS.drop . fromIntegral
  {-# INLINE dropR #-}

--------------------------------------------------------------------------------
-- Hashing functions

mkR :: Rolling a => Int -> a -> R a
mkR l a  = {-# SCC "mkR" #-} R
  { dat_0 = a
  , dat_l = dropR l' a
  , var_l = l'
  , hsh_a = r1 l' a
  , hsh_b = r2 l' a
  }
 where
  l' = fromIntegral l

r1 :: Rolling a => Word8 -> a -> Word16
r1 l r = {-# SCC "r1" #-} go l (splitR r) 0
 where
  go !i !(!h,t) !s = case i of
    0 -> s + fromIntegral h
    _ -> go (i-1) (splitR t) (s + fromIntegral h)

r2 :: Rolling a => Word8 -> a -> Word16
r2 l r = {-# SCC "r2" #-} go (fromIntegral l+1) (splitR r) 0
 where
  go !i !(!h,t) !s = case i of
    1 -> s + fromIntegral h
    _ -> go (i-1) (splitR t) (s + i * fromIntegral h)
