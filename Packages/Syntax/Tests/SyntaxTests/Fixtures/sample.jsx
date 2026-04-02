import React from 'react';

export function Button({ label, onClick }) {
  return (
    <button className="btn" onClick={onClick}>
      {label}
    </button>
  );
}

const App = () => (
  <main>
    <h1>Hello JSX</h1>
    <Button label="Click" onClick={() => console.log('clicked')} />
  </main>
);

export default App;
