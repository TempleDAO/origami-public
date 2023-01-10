import styled from 'styled-components';
import { TypedFieldState } from '@/utils/fields/hooks';

interface FieldProps<T> {
  state: TypedFieldState<T>;
  disabled?: boolean;
  placeholder?: string;
}

export function Field({ state, disabled, placeholder }: FieldProps<unknown>) {
  return (
    <InputHolder>
      <Input
        value={state.text}
        onChange={(e) => state.setText(e.target.value)}
        placeholder={placeholder}
        disabled={disabled}
      />
      {state.isValid() ? undefined : (
        <ValidationError> ← {state.validationError()}</ValidationError>
      )}
    </InputHolder>
  );
}

const InputHolder = styled.div`
  display: flex;
  flex-direction: row;
  gap: 10px;
  align-items: center;
  margin: 10px;
`;

const Input = styled.input`
  font-size: 1rem;
  padding: 8px;
  color: ${({ theme }) => theme.colors.white};
  background-color: ${({ theme }) => theme.colors.bgMid};
  border-radius: 8px;
  border: 2px solid ${({ theme }) => theme.colors.greyDark};

  &:focus-within {
    border: 2px solid white;
  }
`;

const ValidationError = styled.div`
  font-size: 1rem;
  padding-left: calc(2 * 8px);
  color: #ffa0a0;
`;
