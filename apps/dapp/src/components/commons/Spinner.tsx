import { MotionProps } from 'framer-motion';
import { motion } from 'framer-motion';
import styled from 'styled-components';

type Size = 'small' | 'medium' | 'large';

type SpinnerProps = {
  customSize?: number;
  size?: Size;
};

const SIZES: { [Key in Size]: number } = {
  small: 10,
  medium: 20,
  large: 100,
};

export const Spinner = (props: SpinnerProps) => {
  const { size = 'small', customSize } = props;
  const itemSize = customSize ?? SIZES[size];

  const container = {
    hidden: { rotate: 0 },
    visible: {
      rotate: [0, 0, 0, 180, 180, 180],
      transition: {
        staggerChildren: 0.2,
        repeat: Infinity,
        repeatDelay: 0.5,
        duration: 2,
        times: [0, 0.5, 0.6, 0.7, 0.95, 1],
      },
    },
  };

  const item = {
    // @ts-ignore
    hidden: (custom) => ({
      y: 0,
      x: 0,
      scale: 0,
      opacity: 0,
      rotate: custom.rotate,
    }),
    // @ts-ignore
    visible: (custom) => ({
      y: custom.y,
      x: custom.x,
      scale: [0, 1, 1, 1, 1, 0],
      opacity: [0, 1, 1, 1, 1, 0],
      rotate: custom.rotate,
      transition: {
        duration: 2,
        repeat: Infinity,
        repeatDelay: 0.5,
        times: custom.times,
      },
    }),
  };

  // Include a small gap such that there's a small blank space between items
  // to look like a fortune teller
  const scaledItemSize = 0.95 * itemSize;
  return (
    <LoaderContainer
      variants={container}
      initial="hidden"
      animate="visible"
      itemSize={itemSize}
    >
      <LoaderItem
        custom={{
          rotate: 270,
          x: [
            0,
            scaledItemSize,
            scaledItemSize,
            scaledItemSize,
            scaledItemSize,
            0,
          ],
          y: [
            0,
            scaledItemSize,
            scaledItemSize,
            scaledItemSize,
            scaledItemSize,
            0,
          ],
          times: [0.0, 0.1, 0.15, 0.85, 0.9, 1],
        }}
        className={'topLeft'}
        itemSize={itemSize}
        variants={item}
      />
      <LoaderItem
        custom={{
          rotate: 0,
          x: [
            0,
            -scaledItemSize,
            -scaledItemSize,
            -scaledItemSize,
            -scaledItemSize,
            0,
          ],
          y: [
            0,
            scaledItemSize,
            scaledItemSize,
            scaledItemSize,
            scaledItemSize,
            0,
          ],
          times: [0.0, 0.1, 0.15, 0.75, 0.8, 0.9],
        }}
        className={'topRight'}
        itemSize={itemSize}
        variants={item}
      />
      <LoaderItem
        custom={{
          rotate: 90,
          x: [
            0,
            -scaledItemSize,
            -scaledItemSize,
            -scaledItemSize,
            -scaledItemSize,
            0,
          ],
          y: [
            0,
            -scaledItemSize,
            -scaledItemSize,
            -scaledItemSize,
            -scaledItemSize,
            0,
          ],
          times: [0.0, 0.1, 0.15, 0.65, 0.7, 0.8],
        }}
        className={'bottomRight'}
        itemSize={itemSize}
        variants={item}
      />
      <LoaderItem
        custom={{
          rotate: 180,
          x: [
            0,
            scaledItemSize,
            scaledItemSize,
            scaledItemSize,
            scaledItemSize,
            0,
          ],
          y: [
            0,
            -scaledItemSize,
            -scaledItemSize,
            -scaledItemSize,
            -scaledItemSize,
            0,
          ],
          times: [0.0, 0.1, 0.15, 0.55, 0.6, 0.7],
        }}
        className={'bottomLeft'}
        itemSize={itemSize}
        variants={item}
      />
    </LoaderContainer>
  );
};

interface LoaderContainerProps extends MotionProps {
  itemSize: number;
}

export const LoaderContainer = motion(
  styled('ul')<LoaderContainerProps>(({ theme, itemSize }) => ({
    borderColor: `${theme.colors.white} transparent`,
    position: 'relative',
    padding: 0,
    width: `${itemSize * 2}px`,
    height: `${itemSize * 2}px`,
    margin: 0,
    listStyle: 'none',
  }))
);

interface LoaderItemProps extends MotionProps {
  itemSize: number;
  className: 'topRight' | 'topLeft' | 'bottomRight' | 'bottomLeft';
}

const LoaderItem = motion(
  styled('li')<LoaderItemProps>(({ theme, itemSize }) => ({
    position: 'absolute',
    width: 0,
    height: 0,
    borderStyle: 'solid',
    borderWidth: `0 ${itemSize}px ${itemSize}px 0`,

    '&.topLeft': {
      top: `-${itemSize}px`,
      left: `-${itemSize}px`,
      borderColor: `${theme.colors.white} transparent`,
    },

    '&.topRight': {
      top: `-${itemSize}px`,
      right: `-${itemSize}px`,
      borderColor: `${theme.colors.white} transparent`,
    },
    '&.bottomRight': {
      bottom: `-${itemSize}px`,
      right: `-${itemSize}px`,
      borderColor: `${theme.colors.white} transparent`,
    },
    '&.bottomLeft': {
      bottom: `-${itemSize}px`,
      left: `-${itemSize}px`,
      borderColor: `${theme.colors.white} transparent`,
    },
  }))
);
