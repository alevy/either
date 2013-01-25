{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Control.Monad.Trans.Either
  ( EitherT(..)
  , eitherT
  , bimapEitherT
  , mapEitherT
  , hoistEither
  , left
  , right
  ) where

import Control.Applicative
import Control.Monad (liftM)
import Control.Monad.Error.Class
import Control.Monad.Fix
import Control.Monad.IO.Class
import Control.Monad.Reader.Class
import Control.Monad.State (MonadState,get,put)
import Control.Monad.Trans.Class
import Control.Monad.Writer.Class
import Control.Monad.Random (MonadRandom,getRandom,getRandoms,getRandomR,getRandomRs)
import Data.Foldable
import Data.Function (on)
import Data.Functor.Bind
import Data.Functor.Plus
import Data.Traversable
import Data.Semigroup

newtype EitherT e m a = EitherT { runEitherT :: m (Either e a) }

instance Show (m (Either e a)) => Show (EitherT e m a) where
  showsPrec d (EitherT m) = showParen (d > 10) $
    showString "EitherT " . showsPrec 11 m
  {-# INLINE showsPrec #-}

instance Read (m (Either e a)) => Read (EitherT e m a) where
  readsPrec d = readParen (d > 10)
    (\r' -> [ (EitherT m, t)
            | ("EitherT", s) <- lex r'
            , (m, t) <- readsPrec 11 s])
  {-# INLINE readsPrec #-}

instance Eq (m (Either e a)) => Eq (EitherT e m a) where
  (==) = (==) `on` runEitherT
  {-# INLINE (==) #-}

instance Ord (m (Either e a)) => Ord (EitherT e m a) where
  compare = compare `on` runEitherT
  {-# INLINE compare #-}

eitherT :: Monad m => (a -> m c) -> (b -> m c) -> EitherT a m b -> m c
eitherT f g (EitherT m) = m >>= \z -> case z of
  Left a -> f a
  Right b -> g b
{-# INLINE eitherT #-}

left :: Monad m => e -> EitherT e m a
left = EitherT . return . Left
{-# INLINE left #-}

right :: Monad m => a -> EitherT e m a
right = return
{-# INLINE right #-}

bimapEitherT :: Functor m => (e -> f) -> (a -> b) -> EitherT e m a -> EitherT f m b
bimapEitherT f g (EitherT m) = EitherT (fmap h m) where
  h (Left e)  = Left (f e)
  h (Right a) = Right (g a)
{-# INLINE bimapEitherT #-}

hoistEither :: Monad m => Either e a -> EitherT e m a
hoistEither = EitherT . return
{-# INLINE hoistEither #-}

instance Functor m => Functor (EitherT e m) where
  fmap f = EitherT . fmap (fmap f) . runEitherT
  {-# INLINE fmap #-}

instance (Functor m, Monad m) => Apply (EitherT e m) where
  EitherT f <.> EitherT v = EitherT $ f >>= \mf -> case mf of
    Left  e -> return (Left e)
    Right k -> v >>= \mv -> case mv of
      Left  e -> return (Left e)
      Right x -> return (Right (k x))
  {-# INLINE (<.>) #-}

instance (Functor m, Monad m) => Applicative (EitherT e m) where
  pure a  = EitherT $ return (Right a)
  {-# INLINE pure #-}
  EitherT f <*> EitherT v = EitherT $ f >>= \mf -> case mf of
    Left  e -> return (Left e)
    Right k -> v >>= \mv -> case mv of
      Left  e -> return (Left e)
      Right x -> return (Right (k x))
  {-# INLINE (<*>) #-}

instance Monad m => Semigroup (EitherT e m a) where
  EitherT m <> EitherT n = EitherT $ m >>= \a -> case a of
    Left _ -> n
    Right r -> return (Right r)
  {-# INLINE (<>) #-}

instance (Functor m, Monad m) => Alt (EitherT e m) where
  (<!>) = (<>)
  {-# INLINE (<!>) #-}

instance (Functor m, Monad m) => Bind (EitherT e m) where
  (>>-) = (>>=)
  {-# INLINE (>>-) #-}

instance Monad m => Monad (EitherT e m) where
  return a = EitherT $ return (Right a)
  {-# INLINE return #-}
  m >>= k  = EitherT $ do
    a <- runEitherT m
    case a of
      Left  l -> return (Left l)
      Right r -> runEitherT (k r)
  {-# INLINE (>>=) #-}

instance Monad m => MonadError e (EitherT e m) where
  throwError = EitherT . return . Left
  {-# INLINE throwError #-}
  EitherT m `catchError` h = EitherT $ m >>= \a -> case a of
    Left  l -> runEitherT (h l)
    Right r -> return (Right r)
  {-# INLINE catchError #-}

instance MonadFix m => MonadFix (EitherT e m) where
  mfix f = EitherT $ mfix $ \a -> runEitherT $ f $ case a of
    Right r -> r
    _       -> error "empty mfix argument"
  {-# INLINE mfix #-}

instance MonadTrans (EitherT e) where
  lift = EitherT . liftM Right
  {-# INLINE lift #-}

instance MonadIO m => MonadIO (EitherT e m) where
  liftIO = lift . liftIO
  {-# INLINE liftIO #-}

instance MonadReader r m => MonadReader r (EitherT e m) where
  ask = lift ask
  {-# INLINE ask #-}
  local f (EitherT m) = EitherT (local f m)
  {-# INLINE local #-}

instance MonadState s m => MonadState s (EitherT e m) where
  get = lift get
  {-# INLINE get #-}
  put = lift . put
  {-# INLINE put #-}

instance MonadWriter s m => MonadWriter s (EitherT e m) where
  tell = lift . tell
  {-# INLINE tell #-}
  listen = mapEitherT $ \ m -> do
    (a, w) <- listen m
    return $! fmap (\ r -> (r, w)) a
  {-# INLINE listen #-}
  pass = mapEitherT $ \ m -> pass $ do
    a <- m
    return $! case a of
        Left  l      -> (Left  l, id)
        Right (r, f) -> (Right r, f)
  {-# INLINE pass #-}

-- | Map the unwrapped computation using the given function.
--
-- * @'runEitherT' ('mapEitherT' f m) = f ('runEitherT' m@)
mapEitherT :: (m (Either e a) -> n (Either e' b)) -> EitherT e m a -> EitherT e' n b
mapEitherT f m = EitherT $ f (runEitherT m)

instance MonadRandom m => MonadRandom (EitherT e m) where
  getRandom   = lift getRandom
  getRandoms  = lift getRandoms
  getRandomR  = lift . getRandomR
  getRandomRs = lift . getRandomRs

instance Foldable m => Foldable (EitherT e m) where
  foldMap f = foldMap (either mempty f) . runEitherT

instance Traversable f => Traversable (EitherT e f) where
  traverse f (EitherT a) =
    EitherT <$> traverse (either (pure . Left) (fmap Right . f)) a
